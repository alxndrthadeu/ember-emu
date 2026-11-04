import Foundation
import ZIPFoundation

/// Turns a .zip or a folder from the Files app into a game folder
/// under Documents/Games.
enum GameImporter {
    enum ImportError: LocalizedError {
        case notAGame(String)
        case unsupported(String)

        var errorDescription: String? {
            switch self {
            case .notAGame(let name):
                "“\(name)” não parece um jogo de RPG Maker XP, VX ou VX Ace."
            case .unsupported(let name):
                "Ainda não dá para importar “\(name)”. Use um .zip ou uma pasta."
            }
        }
    }

    static var gamesFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Games", isDirectory: true)
    }

    /// Imports one item. Returns the new game's id.
    ///
    /// Work happens in a scratch folder, and the game moves into
    /// Documents/Games only once it is complete, so a failed import
    /// never leaves half a game in the library.
    static func importItem(at url: URL) throws -> String {
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
        } else if url.pathExtension.lowercased() == "zip" {
            let archive = scratch.appendingPathComponent(name)
            try coordinatedCopy(from: url, to: archive)
            unpacked = scratch.appendingPathComponent("unzipped", isDirectory: true)
            try fm.unzipItem(at: archive, to: unpacked)
            try? fm.removeItem(at: archive)
        } else {
            throw ImportError.unsupported(name)
        }

        removeMacMetadata(in: unpacked)

        guard let root = GameFolder.findRoot(in: unpacked) else {
            throw ImportError.notAGame(name)
        }

        let title = GameFolder.title(in: root)
            ?? (name as NSString).deletingPathExtension
        try fm.createDirectory(at: gamesFolder, withIntermediateDirectories: true)
        let id = uniqueID(for: title)
        try fm.moveItem(at: root, to: gamesFolder.appendingPathComponent(id, isDirectory: true))
        return id
    }

    /// Zips made on a Mac carry metadata the game must never see:
    /// "._name" twins of every file, a __MACOSX folder, .DS_Store.
    /// Games scan their own folders (Pokémon Flux mounts every file
    /// with ".fpk" in its name), and "._Data_0.fpk" breaks them.
    ///
    /// FileManager hides "._" files from every listing it offers, but
    /// the engine lists folders with POSIX calls and sees them. So
    /// this walks the tree with readdir.
    private static func removeMacMetadata(in folder: URL) {
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
