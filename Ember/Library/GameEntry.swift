import Foundation

/// A game in the library: one folder under Documents/Games.
struct GameEntry: Identifiable, Hashable {
    /// The folder name under Documents/Games. Stable: saves are kept
    /// under the same id.
    let id: String
    let title: String
    /// The game's root (the folder with Game.ini, Data/, ...).
    let folder: URL
    let addedAt: Date

    init?(folder: URL) {
        guard GameFolder.looksLikeGame(folder) else { return nil }
        self.id = folder.lastPathComponent
        self.folder = folder
        self.title = GameFolder.title(in: folder) ?? folder.lastPathComponent
        let values = try? folder.resourceValues(forKeys: [.creationDateKey])
        self.addedAt = values?.creationDate ?? .distantPast
    }

    /// The Ruby the game was made for, when the folder gives it away.
    /// Phase 2 replaces this guess with a real version detector.
    var rubyVersion: MKXPRubyVersion? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        if names.contains(where: { $0.lowercased().contains("ruby3") }) {
            return MKXP_RUBY_31
        }
        return nil
    }
}

/// What a RPG Maker XP / VX / VX Ace game folder looks like.
enum GameFolder {
    private static let archiveExtensions = ["rgssad", "rgss2a", "rgss3a"]
    private static let scriptFiles = ["Scripts.rxdata", "Scripts.rvdata", "Scripts.rvdata2"]

    /// A game folder holds a .ini with a [Game] section, packed data
    /// (Game.rgssad and siblings), or Data/Scripts.
    static func looksLikeGame(_ folder: URL) -> Bool {
        let names = contents(of: folder)
        if names.contains(where: { archiveExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) {
            return true
        }
        let data = folder.appendingPathComponent("Data")
        if contents(of: data).contains(where: { scriptFiles.contains($0) }) {
            return true
        }
        return iniFile(in: folder) != nil
    }

    /// Finds the game inside an extracted archive or a picked folder.
    /// Zips often wrap the game in one or two extra folders.
    static func findRoot(in folder: URL, depth: Int = 3) -> URL? {
        if looksLikeGame(folder) { return folder }
        guard depth > 0 else { return nil }
        let children = contents(of: folder)
            .filter { !$0.hasPrefix(".") && $0 != "__MACOSX" }
            .map { folder.appendingPathComponent($0) }
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        for child in children {
            if let root = findRoot(in: child, depth: depth - 1) { return root }
        }
        return nil
    }

    /// The Title= line of the [Game] section.
    static func title(in folder: URL) -> String? {
        guard let ini = iniFile(in: folder) else { return nil }
        for line in iniLines(ini) {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "title" {
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// The RPG Maker .ini: the one with a [Game] section. Games ship
    /// other .ini files too (patchers, plugins).
    private static func iniFile(in folder: URL) -> URL? {
        contents(of: folder)
            .filter { $0.lowercased().hasSuffix(".ini") }
            .map { folder.appendingPathComponent($0) }
            .first { iniLines($0).contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == "[game]" } }
    }

    private static func iniLines(_ url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .windowsCP1252)
        else { return [] }
        return text.components(separatedBy: .newlines)
    }

    private static func contents(of folder: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }
}
