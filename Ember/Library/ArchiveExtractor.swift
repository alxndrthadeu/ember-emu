import Foundation

/// Unpacks .rar (RAR4 and RAR5) and .7z with the libarchive that ships
/// in iOS. Zips stay with ZIPFoundation (GameImporter).
enum ArchiveExtractor {
    static let extensions: Set<String> = ["rar", "7z"]

    enum ExtractError: LocalizedError {
        case cannotOpen(String)
        case encrypted
        case multiVolume
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cannotOpen(let detail):
                "Não deu para abrir o arquivo compactado (\(detail))."
            case .encrypted:
                "O arquivo está protegido por senha. Extraia no computador e importe a pasta ou um .zip."
            case .multiVolume:
                "Este .rar está dividido em partes (part1, part2…). Junte as partes no computador e importe de novo."
            case .failed(let detail):
                "A extração parou no meio (\(detail))."
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

        guard let reader = archive_read_new() else { throw ExtractError.cannotOpen("memória") }
        defer { archive_read_free(reader) }
        archive_read_support_format_all(reader)
        archive_read_support_filter_all(reader)

        guard let writer = archive_write_disk_new() else { throw ExtractError.cannotOpen("memória") }
        defer { archive_write_free(writer) }
        let flags = ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_SECURE_NODOTDOT
            | ARCHIVE_EXTRACT_SECURE_SYMLINKS
        archive_write_disk_set_options(writer, flags)

        guard archive_read_open_filename(reader, archive.path, 1 << 16) == ARCHIVE_OK else {
            throw ExtractError.cannotOpen(message(reader))
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
        archive_error_string(archive).map { String(cString: $0) } ?? "erro desconhecido"
    }
}
