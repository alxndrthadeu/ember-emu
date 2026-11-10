import Foundation
import ZIPFoundation

/// Turns a .zip, .rar, .7z or a folder from the Files app into a game
/// folder under Documents/Games.
enum GameImporter {
    enum ImportError: LocalizedError {
        case notAGame(String)
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .notAGame(let name):
                String(localized: "“\(name)” não parece um jogo de RPG Maker XP, VX ou VX Ace.")
            case .unsupported(let name):
                String(localized: "Ainda não dá para importar “\(name)”. Use .zip, .rar, .7z, .exe autoextraível ou uma pasta.")
            }
        }
    }

    static var gamesFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Games", isDirectory: true)
    }

    /// Archive types the importer unpacks.
    static let archiveExtensions: Set<String> = ArchiveExtractor.extensions.union(["zip"])

    enum Imported {
        case game(String)
        case rtp(RTPStore.Kind)
    }

    /// Imports one item: a game, or an RTP (Graphics and Audio with no
    /// game), which goes to the RTP store.
    ///
    /// Work happens in a scratch folder, and the game moves into
    /// Documents/Games only once it is complete, so a failed import
    /// never leaves half a game in the library. Archives are read where
    /// they are, without a copy first: games are big.
    ///
    /// `discardArchive` sends an imported .zip/.rar/.7z to the trash
    /// (Recently Deleted in the Files app) to free the space it takes.
    static func importItem(at url: URL, discardArchive: Bool = false) throws -> Imported {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        let name = url.lastPathComponent
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true

        let unpacked: URL
        if isFolder {
            unpacked = scratch.appendingPathComponent(name, isDirectory: true)
            try coordinatedCopy(from: url, to: unpacked)
        } else if archiveExtensions.contains(url.pathExtension.lowercased()) {
            unpacked = scratch.appendingPathComponent("unpacked", isDirectory: true)
            let isZip = url.pathExtension.lowercased() == "zip"
            try coordinatedRead(url) { readable in
                if isZip {
                    try fm.unzipItem(at: readable, to: unpacked)
                } else {
                    try ArchiveExtractor.extract(readable, to: unpacked)
                }
            }
        } else {
            throw ImportError.unsupported(name)
        }

        removeMacMetadata(in: unpacked)

        // Some downloads are a .zip holding an installer .exe.
        let inner = GameFolder.findRoot(in: unpacked) == nil && RTPStore.findRoot(in: unpacked) == nil
            ? try unpackInstallers(in: unpacked, scratch: scratch) : nil
        let searched = inner ?? unpacked

        guard let root = GameFolder.findRoot(in: searched) else {
            if let (rtp, kind) = RTPStore.findRoot(in: searched) {
                try RTPStore.install(rtp, as: kind)
                if discardArchive, !isFolder { trash(url) }
                return .rtp(kind)
            }
            throw ImportError.notAGame(name)
        }

        let title = GameFolder.title(in: root)
            ?? (name as NSString).deletingPathExtension
        try fm.createDirectory(at: gamesFolder, withIntermediateDirectories: true)
        let id = uniqueID(for: title)
        try fm.moveItem(at: root, to: gamesFolder.appendingPathComponent(id, isDirectory: true))

        if discardArchive, !isFolder {
            trash(url)
        }
        return .game(id)
    }

    /// Extracts the self-extracting .exe files found near the top of an
    /// unpacked download. Returns the folder that holds a game, or nil.
    /// A plain program (Game.exe of a game, a launcher) is skipped.
    private static func unpackInstallers(in folder: URL, scratch: URL) throws -> URL? {
        let fm = FileManager.default
        var installers: [URL] = []
        var queue: [(URL, Int)] = [(folder, 0)]
        while let (dir, depth) = queue.popLast() {
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where !name.hasPrefix(".") {
                let url = dir.appendingPathComponent(name)
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if depth < 2 { queue.append((url, depth + 1)) }
                } else if url.pathExtension.lowercased() == "exe" {
                    installers.append(url)
                }
            }
        }
        var lastError: Error?
        for (index, exe) in installers.enumerated() {
            let target = scratch.appendingPathComponent("installer-\(index)", isDirectory: true)
            do {
                try ArchiveExtractor.extract(exe, to: target)
            } catch {
                lastError = error
                continue
            }
            removeMacMetadata(in: target)
            if GameFolder.findRoot(in: target) != nil || RTPStore.findRoot(in: target) != nil { return target }
        }
        // Say why, when the only lead was an unusual installer.
        if let lastError, case ArchiveExtractor.ExtractError.virtualBox = lastError { throw lastError }
        return nil
    }

    /// Moves an imported archive to the trash, so it can still be
    /// recovered from Recently Deleted. Falls back to deleting it.
    private static func trash(_ url: URL) {
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinatorError) { writable in
            do {
                try FileManager.default.trashItem(at: writable, resultingItemURL: nil)
            } catch {
                try? FileManager.default.removeItem(at: writable)
            }
        }
    }

    /// Reads a file from iCloud Drive or another app, which may still
    /// be downloading, through NSFileCoordinator.
    private static func coordinatedRead(_ source: URL, _ body: (URL) throws -> Void) throws {
        var coordinatorError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinatorError) { readable in
            do { try body(readable) } catch { bodyError = error }
        }
        if let error = coordinatorError ?? bodyError { throw error }
    }

    /// Zips made on a Mac carry metadata the game must never see:
    /// "._name" twins of every file, a __MACOSX folder, .DS_Store.
    /// Games scan their own folders (Pokémon Flux mounts every file
    /// with ".fpk" in its name), and "._Data_0.fpk" breaks them.
    ///
    /// FileManager hides "._" files from every listing it offers, but
    /// the engine lists folders with POSIX calls and sees them. So
    /// this walks the tree with readdir.
    static func removeMacMetadata(in folder: URL) {
        let fm = FileManager.default
        var pending = [folder.path]
        while let path = pending.popLast() {
            for (name, isDirectory) in directoryEntries(at: path) {
                let child = (path as NSString).appendingPathComponent(name)
                if name == "__MACOSX" || name.hasPrefix("._") || name == ".DS_Store" {
                    try? fm.removeItem(atPath: child)
                } else if isDirectory {
                    pending.append(child)
                }
            }
        }
    }

    /// Every entry in a folder, "._" files included.
    private static func directoryEntries(at path: String) -> [(name: String, isDirectory: Bool)] {
        guard let dir = opendir(path) else { return [] }
        defer { closedir(dir) }
        var entries: [(String, Bool)] = []
        while let entry = readdir(dir) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
            }
            guard name != ".", name != ".." else { continue }
            entries.append((name, entry.pointee.d_type == DT_DIR))
        }
        return entries
    }

    /// Files from iCloud Drive or another app may still be downloading,
    /// so the copy goes through NSFileCoordinator.
    private static func coordinatedCopy(from source: URL, to target: URL) throws {
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinatorError) { readable in
            do {
                try FileManager.default.copyItem(at: readable, to: target)
            } catch {
                copyError = error
            }
        }
        if let error = coordinatorError ?? copyError { throw error }
    }

    /// A folder name from the title: readable in the Files app, and
    /// unique in the library ("Pokemon Flux", "Pokemon Flux 2", ...).
    private static func uniqueID(for title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|").union(.controlCharacters)
        var base = title.components(separatedBy: forbidden).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if base.isEmpty { base = "Jogo" }

        var id = base
        var counter = 2
        while FileManager.default.fileExists(atPath: gamesFolder.appendingPathComponent(id).path) {
            id = "\(base) \(counter)"
            counter += 1
        }
        return id
    }
}
