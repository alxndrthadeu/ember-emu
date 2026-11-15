import Foundation
import ZIPFoundation

/// A game's saves, kept exactly as RPG Maker writes them, where the
/// game looks for them. The engine mimics Windows, so the files are
/// the same as on a PC and move both ways unchanged:
///
/// | Game                     | Files                          | On a PC                        | In Ember                  |
/// | ------------------------ | ------------------------------ | ------------------------------ | ------------------------- |
/// | Plain RPG Maker          | Save1.rxdata, Save01.rvdata2   | the game folder                | Games/<id>/               |
/// | Pokémon Essentials       | Game.rxdata, Game_1.rxdata     | %APPDATA%\<game title>\        | UserData/<id>/            |
/// | Portable saves           | anything                       | the game folder's Save Data\   | Games/<id>/Save Data/     |
///
/// An export puts both areas at the root of one .zip. An import sends
/// each file back where the game will read it, and copies whatever it
/// replaces into Documents/Backups first.
enum SaveManager {
    struct SaveFile: Identifiable {
        /// Path inside an export: relative to the area it lives in.
        let id: String
        let url: URL
        let modified: Date
        let size: Int
    }

    enum SaveError: LocalizedError {
        case noSaves(String)
        case nothingToImport

        var errorDescription: String? {
            switch self {
            case .noSaves(let title):
                String(localized: "Ainda não há saves de \(title).")
            case .nothingToImport:
                String(localized: "Nenhum arquivo de save encontrado no que foi escolhido.")
            }
        }
    }

    // MARK: Where saves live

    /// Files the engine or the app write in UserData that are not saves.
    private static let notSaves: Set<String> = ["systemout.txt", "cover.jpg", ".ds_store"]
    private static let saveExtensions: Set<String> = ["rxdata", "rvdata", "rvdata2"]

    static func backupsFolder(for game: GameEntry) -> URL {
        documents.appendingPathComponent("Backups/\(game.id)", isDirectory: true)
    }

    /// Every save of the game, in both areas.
    static func saves(for game: GameEntry) -> [SaveFile] {
        gameFolderSaves(game) + userDataSaves(game)
    }

    /// Plain RPG Maker saves and portable "Save Data" in the game folder.
    private static func gameFolderSaves(_ game: GameEntry) -> [SaveFile] {
        var result: [SaveFile] = []
        for name in contents(of: game.folder) {
            let url = game.folder.appendingPathComponent(name)
            if isDirectory(url) {
                if name.caseInsensitiveCompare("Save Data") == .orderedSame {
                    result += files(under: url, prefix: name)
                }
            } else if isGameFolderSaveName(name) {
                result += [saveFile(url, id: name)].compactMap { $0 }
            }
        }
        return result
    }

    /// Everything a game wrote through System.data_directory or the
    /// faked %APPDATA%.
    private static func userDataSaves(_ game: GameEntry) -> [SaveFile] {
        files(under: GameStorage.userDataFolder(for: game), prefix: "")
            .filter { !notSaves.contains(($0.id as NSString).lastPathComponent.lowercased()) }
    }

    /// "Save1.rxdata", "Save01.rvdata2", and the "Game.rxdata" of
    /// older Essentials games that keep it next to the executable.
    static func isGameFolderSaveName(_ name: String) -> Bool {
        let lower = name.lowercased()
        let base = lower.hasSuffix(".bak") ? String(lower.dropLast(4)) : lower
        let ext = (base as NSString).pathExtension
        let stem = (base as NSString).deletingPathExtension
        guard saveExtensions.contains(ext) else { return false }
        return stem.range(of: #"^save\d*$"#, options: .regularExpression) != nil
            || stem.range(of: #"^game(_\d+)?$"#, options: .regularExpression) != nil
    }

    // MARK: Export

    /// A .zip with the saves at its root, the way the game folder or
    /// %APPDATA%\<title>\ holds them on a PC.
    static func export(_ game: GameEntry) throws -> URL {
        let saves = saves(for: game)
        guard !saves.isEmpty else { throw SaveError.noSaves(game.title) }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("Export-\(UUID().uuidString)")
        let staging = work.appendingPathComponent("saves")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        for save in saves {
            let target = staging.appendingPathComponent(save.id)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: save.url, to: target)
        }

        let zip = work.appendingPathComponent("\(game.title) - saves.zip")
        try fm.zipItem(at: staging, to: zip, shouldKeepParent: false)
        return zip
    }

    // MARK: Import

    /// Imports saves from .zip files, folders or single save files.
    /// Returns how many files were placed.
    static func importSaves(from urls: [URL], into game: GameEntry) throws -> Int {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("SaveImport-\(UUID().uuidString)")
        let incoming = work.appendingPathComponent("incoming")
        try fm.createDirectory(at: incoming, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // Gather everything into one folder.
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if url.pathExtension.lowercased() == "zip" {
                let unpacked = work.appendingPathComponent("zip-\(UUID().uuidString)")
                try fm.unzipItem(at: url, to: unpacked)
                try mergeContents(of: unwrap(unpacked), into: incoming)
            } else if isDirectory(url) {
                try mergeContents(of: url, into: incoming)
            } else {
                try replace(incoming.appendingPathComponent(url.lastPathComponent), with: url)
            }
        }
        GameImporter.removeMacMetadata(in: incoming)

        let files = files(under: incoming, prefix: "")
            .filter { !notSaves.contains(($0.id as NSString).lastPathComponent.lowercased()) }
        guard !files.isEmpty else { throw SaveError.nothingToImport }

        let stamp = Self.stamp()
        for file in files {
            let target = destination(for: file.id, in: game)
            if fm.fileExists(atPath: target.path) {
                try backUp(target, relativeID: file.id, of: game, stamp: stamp)
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try replace(target, with: file.url)
        }
        return files.count
    }

    /// Where the game will read a save named `id`.
    private static func destination(for id: String, in game: GameEntry) -> URL {
        let inGameFolder = game.folder.appendingPathComponent(id)
        let inUserData = GameStorage.userDataFolder(for: game).appendingPathComponent(id)
        let fm = FileManager.default
        // A file with the same name already shows where the game keeps it.
        if fm.fileExists(atPath: inGameFolder.path) { return inGameFolder }
        if fm.fileExists(atPath: inUserData.path) { return inUserData }

        let first = id.split(separator: "/").first.map(String.init) ?? id
        if first.caseInsensitiveCompare("Save Data") == .orderedSame { return inGameFolder }
        if !id.contains("/"), (id as NSString).lastPathComponent.lowercased().hasPrefix("save"),
           isGameFolderSaveName(id) {
            return inGameFolder
        }
        return inUserData
    }

    /// Before a game is deleted: its game-folder saves would go with
    /// it, so they move to Backups. UserData stays and is found again
    /// if the game comes back under the same name.
    /// Deletes one save: it goes to Documents/Backups/<id>/<date>/ first.
    static func delete(_ save: SaveFile, of game: GameEntry) throws {
        try backUp(save.url, relativeID: save.id, of: game, stamp: stamp(), move: true)
        SaveThumbnails.remove(save, gameID: game.id)
    }

    static func stashGameFolderSaves(of game: GameEntry) {
        let stamp = Self.stamp()
        for save in gameFolderSaves(game) {
            try? backUp(save.url, relativeID: save.id, of: game, stamp: stamp, move: true)
        }
    }

    // MARK: Helpers

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static func backUp(_ url: URL, relativeID: String, of game: GameEntry,
                               stamp: String, move: Bool = false) throws {
        let fm = FileManager.default
        let target = backupsFolder(for: game).appendingPathComponent(stamp).appendingPathComponent(relativeID)
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: target)
        if move {
            try fm.moveItem(at: url, to: target)
        } else {
            try fm.copyItem(at: url, to: target)
        }
    }

    private static func replace(_ target: URL, with source: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: target)
        try fm.copyItem(at: source, to: target)
    }

    private static func mergeContents(of folder: URL, into target: URL) throws {
        for name in contents(of: folder) {
            try replace(target.appendingPathComponent(name), with: folder.appendingPathComponent(name))
        }
    }

    /// A zip of a save folder often wraps it in one more folder
    /// ("Pokemon Flux/Game_1.rxdata"): step into it.
    private static func unwrap(_ folder: URL) -> URL {
        var current = folder
        for _ in 0..<3 {
            let names = contents(of: current).filter { !$0.hasPrefix(".") && $0 != "__MACOSX" }
            guard names.count == 1 else { break }
            let only = current.appendingPathComponent(names[0])
            guard isDirectory(only),
                  names[0].caseInsensitiveCompare("Save Data") != .orderedSame
            else { break }
            current = only
        }
        return current
    }

    private static func files(under folder: URL, prefix: String) -> [SaveFile] {
        var result: [SaveFile] = []
        for name in contents(of: folder) where !name.hasPrefix(".") {
            let url = folder.appendingPathComponent(name)
            let id = prefix.isEmpty ? name : "\(prefix)/\(name)"
            if isDirectory(url) {
                result += files(under: url, prefix: id)
            } else if let file = saveFile(url, id: id) {
                result.append(file)
            }
        }
        return result
    }

    private static func saveFile(_ url: URL, id: String) -> SaveFile? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return SaveFile(id: id, url: url,
                        modified: values?.contentModificationDate ?? .distantPast,
                        size: values?.fileSize ?? 0)
    }

    private static func contents(of folder: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }
}
