import Foundation

/// Unpacks .rar (RAR4 and RAR5) and .7z with the libarchive that ships
/// in iOS. Zips stay with ZIPFoundation (GameImporter).
enum ArchiveExtractor {
    static let extensions: Set<String> = ["rar", "7z", "exe"]

    enum ExtractError: LocalizedError {
        case cannotOpen(String)
        case encrypted
        case multiVolume
        case failed(String)
        /// A Windows program with no archive inside.
        case plainProgram(String)
        /// Packed with Enigma Virtual Box: a virtual file system, not an archive.
        case virtualBox(String)

        var errorDescription: String? {
            switch self {
            case .cannotOpen(let detail):
                String(localized: "Não deu para abrir o arquivo compactado (\(detail)).")
            case .encrypted:
                String(localized: "O arquivo está protegido por senha. Extraia no computador e importe a pasta ou um .zip.")
            case .multiVolume:
                String(localized: "Este .rar está dividido em partes (part1, part2…). Junte as partes no computador e importe de novo.")
            case .failed(let detail):
                String(localized: "A extração parou no meio (\(detail)).")
            case .plainProgram(let name):
                String(localized: "“\(name)” é um programa do Windows, não um jogo compactado. Importe a pasta do jogo, ou um .zip dela.")
            case .virtualBox(let name):
                String(localized: "“\(name)” foi empacotado com o Enigma Virtual Box, que o Ember ainda não abre. Procure a versão em .zip do jogo, ou extraia no computador com o EnigmaVBUnpacker.")
            }
        }
    }

    /// Extracts every entry of `archive` under `destination`. Entries
    /// that try to leave the folder are skipped: absolute paths are made
    /// relative here, and libarchive refuses "../" and symlink tricks.
    /// (Its no-absolute-paths flag cannot be used: the target path this
    /// code builds is absolute.)
    static func extract(_ archive: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        guard let reader = archive_read_new() else { throw ExtractError.cannotOpen(String(localized: "memória")) }
        defer { archive_read_free(reader) }
        archive_read_support_format_all(reader)
        archive_read_support_filter_all(reader)

        guard let writer = archive_write_disk_new() else { throw ExtractError.cannotOpen(String(localized: "memória")) }
        defer { archive_write_free(writer) }
        let flags = ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_SECURE_NODOTDOT
            | ARCHIVE_EXTRACT_SECURE_SYMLINKS
        archive_write_disk_set_options(writer, flags)

        // A self-extracting .exe (7-Zip, WinRAR, CAB/IExpress, zip)
        // carries a plain archive after the Windows program: read from
        // where it starts, without copying it out first.
        var source: OffsetSource?
        if archive.pathExtension.lowercased() == "exe" {
            let found = try SelfExtractor.payload(in: archive)
            source = try OffsetSource(url: archive, base: found)
        }
        defer { source?.close() }

        if let source {
            archive_read_set_read_callback(reader, OffsetSource.read)
            archive_read_set_seek_callback(reader, OffsetSource.seek)
            archive_read_set_skip_callback(reader, OffsetSource.skip)
            archive_read_set_callback_data(reader, Unmanaged.passUnretained(source).toOpaque())
            guard archive_read_open1(reader) == ARCHIVE_OK else {
                throw ExtractError.cannotOpen(message(reader))
            }
        } else {
            guard archive_read_open_filename(reader, archive.path, 1 << 16) == ARCHIVE_OK else {
                throw ExtractError.cannotOpen(message(reader))
            }
        }

        var entry: OpaquePointer?
        while true {
            let status = archive_read_next_header(reader, &entry)
            if status == ARCHIVE_EOF { break }
            if status < ARCHIVE_WARN {
                let text = message(reader)
                if text.lowercased().contains("multivolume") || text.lowercased().contains("multi-volume") {
                    throw ExtractError.multiVolume
                }
                throw ExtractError.failed(text)
            }
            guard let entry else { continue }
            if archive_entry_is_encrypted(entry) != 0 { throw ExtractError.encrypted }

            guard let raw = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry) else { continue }
            // Windows archives use backslashes.
            let components = String(cString: raw)
                .replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/")
                .filter { !$0.isEmpty && $0 != "." }
            guard !components.isEmpty, !components.contains("..") else { continue }
            let relative = components.joined(separator: "/")
            let target = destination.appendingPathComponent(relative).path
            archive_entry_set_pathname_utf8(entry, target)

            guard archive_write_header(writer, entry) >= ARCHIVE_WARN else {
                throw ExtractError.failed(message(writer))
            }
            if archive_entry_size(entry) > 0 {
                try copyData(from: reader, to: writer)
            }
            archive_write_finish_entry(writer)
        }
    }

    private static func copyData(from reader: OpaquePointer, to writer: OpaquePointer) throws {
        var buffer: UnsafeRawPointer?
        var size = 0
        var offset: la_int64_t = 0
        while true {
            let status = archive_read_data_block(reader, &buffer, &size, &offset)
            if status == ARCHIVE_EOF { return }
            if status < ARCHIVE_WARN {
                let text = message(reader)
                if text.lowercased().contains("encrypt") || text.lowercased().contains("passphrase") {
                    throw ExtractError.encrypted
                }
                throw ExtractError.failed(text)
            }
            guard archive_write_data_block(writer, buffer, size, offset) >= ARCHIVE_WARN else {
                throw ExtractError.failed(message(writer))
            }
        }
    }

    private static func message(_ archive: OpaquePointer) -> String {
        archive_error_string(archive).map { String(cString: $0) } ?? String(localized: "erro desconhecido")
    }
}

/// Finds the archive inside a self-extracting Windows .exe.
enum SelfExtractor {
    /// Installers keep the archive near the start, after a small
    /// program; a game packed as one big program has none.
    private static let scanLimit = 64 << 20

    /// The offset of the archive inside `exe`.
    static func payload(in exe: URL) throws -> UInt64 {
        let name = exe.lastPathComponent
        guard let handle = try? FileHandle(forReadingFrom: exe) else {
            throw ArchiveExtractor.ExtractError.cannotOpen(name)
        }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: 0)

        let chunk = 1 << 20
        let overlap = 64
        var base: UInt64 = 0
        var carry = Data()
        var sawVirtualBox = false
        while base < UInt64(scanLimit), let data = try? handle.read(upToCount: chunk), !data.isEmpty {
            let window = carry + data
            let windowStart = base - UInt64(carry.count)
            let bytes = [UInt8](window)
            if !sawVirtualBox, window.range(of: Data("EVB\0".utf8)) != nil,
               window.range(of: Data("Enigma".utf8)) != nil {
                sawVirtualBox = true
            }
            var i = 0
            while i + 32 <= bytes.count {
                let offset = windowStart + UInt64(i)
                if offset > 0, isArchive(bytes, at: i, offset: offset, fileSize: fileSize) {
                    return offset
                }
                i += 1
            }
            base += UInt64(data.count)
            carry = Data(window.suffix(overlap))
        }
        if sawVirtualBox { throw ArchiveExtractor.ExtractError.virtualBox(name) }
        // A zip self-extractor is read from its end: libarchive finds it
        // when given the whole file.
        if hasZipDirectory(handle: handle, fileSize: fileSize) { return 0 }
        throw ArchiveExtractor.ExtractError.plainProgram(name)
    }

    private static func isArchive(_ b: [UInt8], at i: Int, offset: UInt64, fileSize: UInt64) -> Bool {
        switch b[i] {
        case 0x37: // 7z
            return b[i + 1] == 0x7A && b[i + 2] == 0xBC && b[i + 3] == 0xAF && b[i + 4] == 0x27 && b[i + 5] == 0x1C
        case 0x52: // Rar!\x1A\x07 00 (RAR4) or 01 00 (RAR5)
            return b[i + 1] == 0x61 && b[i + 2] == 0x72 && b[i + 3] == 0x21 && b[i + 4] == 0x1A && b[i + 5] == 0x07
                && (b[i + 6] == 0x00 || (b[i + 6] == 0x01 && b[i + 7] == 0x00))
        case 0x4D: // MSCF, with the header checks that keep stray bytes out:
            // zero reserved fields, a size that fits, version 1.3.
            guard b[i + 1] == 0x53, b[i + 2] == 0x43, b[i + 3] == 0x46 else { return false }
            let reserved1 = b[i + 4] | b[i + 5] | b[i + 6] | b[i + 7]
            let size = UInt64(b[i + 8]) | UInt64(b[i + 9]) << 8 | UInt64(b[i + 10]) << 16 | UInt64(b[i + 11]) << 24
            let reserved2 = b[i + 12] | b[i + 13] | b[i + 14] | b[i + 15]
            return reserved1 == 0 && reserved2 == 0 && size > 64 && offset + size <= fileSize
                && b[i + 24] == 3 && b[i + 25] == 1
        default:
            return false
        }
    }

    /// The zip end-of-central-directory record, in the last 64 KB.
    private static func hasZipDirectory(handle: FileHandle, fileSize: UInt64) -> Bool {
        let tail = min(fileSize, 66_000)
        try? handle.seek(toOffset: fileSize - tail)
        guard let data = try? handle.read(upToCount: Int(tail)) else { return false }
        return data.range(of: Data([0x50, 0x4B, 0x05, 0x06])) != nil
    }
}

/// Lets libarchive read a file from an offset, as if the file started
/// there.
final class OffsetSource {
    private let fd: Int32
    private let base: Int64
    private let size: Int64
    private var position: Int64 = 0
    private let buffer = UnsafeMutableRawPointer.allocate(byteCount: 1 << 16, alignment: 16)

    init(url: URL, base: UInt64) throws {
        fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw ArchiveExtractor.ExtractError.cannotOpen(url.lastPathComponent) }
        var info = stat()
        fstat(fd, &info)
        self.base = Int64(base)
        size = Int64(info.st_size) - Int64(base)
    }

    func close() {
        Darwin.close(fd)
        buffer.deallocate()
    }

    private static func source(_ client: UnsafeMutableRawPointer?) -> OffsetSource {
        Unmanaged<OffsetSource>.fromOpaque(client!).takeUnretainedValue()
    }

    static let read: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?,
                                     UnsafeMutablePointer<UnsafeRawPointer?>?) -> la_ssize_t = { _, client, out in
        let s = source(client)
        let count = pread(s.fd, s.buffer, 1 << 16, off_t(s.base + s.position))
        guard count >= 0 else { return -1 }
        s.position += Int64(count)
        out?.pointee = UnsafeRawPointer(s.buffer)
        return la_ssize_t(count)
    }

    static let skip: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, la_int64_t) -> la_int64_t = { _, client, request in
        let s = source(client)
        let step = max(0, min(request, s.size - s.position))
        s.position += step
        return step
    }

    static let seek: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, la_int64_t, Int32) -> la_int64_t = { _, client, offset, whence in
        let s = source(client)
        let target: Int64
        switch whence {
        case SEEK_SET: target = offset
        case SEEK_CUR: target = s.position + offset
        case SEEK_END: target = s.size + offset
        default: return -1
        }
        guard target >= 0 else { return -1 }
        s.position = target
        return target
    }
}
