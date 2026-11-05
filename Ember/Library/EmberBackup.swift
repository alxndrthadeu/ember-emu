import Foundation
import ZIPFoundation

/// Ajustes › Backup: everything Ember keeps, in one ".emberbackup" file
/// (a zip) the player saves wherever they like through the Files app:
/// iCloud Drive, Google Drive, Dropbox, a computer.
///
/// Layout inside, the same paths as on the device:
///   Games/<id>/...        Documents (games; only their saves in a saves backup)
///   UserData/<id>/...     Documents (Essentials saves, %APPDATA%)
///   States/ Covers/ RTP/ Skins/   Application Support
///   defaults.plist        settings, names, profiles, history
///   ember-backup.json     what this is
///
/// Restoring never deletes: files it replaces go to
/// Documents/Backups/Restauração <date>/ first, and a game already in
/// the library keeps its own files (only its saves come from the backup).
enum EmberBackup {
    static let fileExtension = "emberbackup"
    private static let manifestName = "ember-backup.json"
    private static let defaultsName = "defaults.plist"

    /// What goes into a backup: the player picks.
    struct Options: Codable, Equatable {
        /// Games whose whole folder goes in (the rest: only their saves,
        /// when `saves` is on).
        var games: Set<String> = []
        var saves = true
        var states = true
        var covers = true
        var rtp = false
        var skins = true
        var settings = true

        var isEmpty: Bool {
            games.isEmpty && !saves && !states && !covers && !rtp && !skins && !settings
        }
    }

    struct Manifest: Codable {
        var format = 1
        let options: Options
        let appVersion: String
        let created: Date
        let games: [String]
    }

    struct Summary {
        var games = 0
        var files = 0
    }

    enum BackupError: LocalizedError {
        case notABackup

        var errorDescription: String? {
            String(localized: "Este arquivo não é um backup do Ember.")
        }
    }

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Making one

    /// Writes the backup to a temporary file and returns it. Files are
    /// stored, not compressed: games are already packed, and storing is
    /// fast even for a few gigabytes.
    static func make(_ options: Options, library games: [GameEntry]) throws -> URL {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("Backup-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Self.stamp(Date())
        let url = folder.appendingPathComponent("Ember \(stamp).\(fileExtension)")
        let archive = try Archive(url: url, accessMode: .create)

        // Games: the whole folder for the ones picked; for the others,
        // the saves they keep in their own folder.
        for game in games {
            if options.games.contains(game.id) {
                try add(folder: "Games/\(game.id)", base: documents, to: archive)
            } else if options.saves {
                for save in SaveManager.saves(for: game) where save.url.path.hasPrefix(game.folder.path + "/") {
                    try add(file: "Games/\(game.id)/\(save.id)", base: documents, to: archive)
                }
            }
        }
        if options.saves { try add(folder: "UserData", base: documents, to: archive) }
        let supportFolders: [(Bool, String)] = [(options.states, "States"), (options.covers, "Covers"),
                                                 (options.rtp, "RTP"), (options.skins, "Skins")]
        for (on, name) in supportFolders where on {
            try add(folder: name, base: support, to: archive)
        }

        // Settings and the rest of UserDefaults (titles, profiles, history).
        if options.settings, let bundleID = Bundle.main.bundleIdentifier,
           let domain = UserDefaults.standard.persistentDomain(forName: bundleID) {
            let data = try PropertyListSerialization.data(fromPropertyList: domain, format: .binary, options: 0)
            try addData(data, path: defaultsName, to: archive)
        }
        let manifest = Manifest(options: options,
                                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                                created: Date(),
                                games: games.filter { options.games.contains($0.id) }.map(\.title))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        try addData(encoder.encode(manifest), path: manifestName, to: archive)
        return url
    }

    private static func add(folder relative: String, base: URL, to archive: Archive) throws {
        let fm = FileManager.default
        let root = base.appendingPathComponent(relative, isDirectory: true)
        guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let file as URL in walker {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  !file.lastPathComponent.hasPrefix("._"), file.lastPathComponent != ".DS_Store"
            else { continue }
            let inner = String(file.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
            try add(file: "\(relative)/\(inner)", base: base, to: archive)
        }
    }

    private static func add(file relative: String, base: URL, to archive: Archive) throws {
        try archive.addEntry(with: relative, relativeTo: base, compressionMethod: .none)
    }

    private static func addData(_ data: Data, path: String, to archive: Archive) throws {
        try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                             compressionMethod: .deflate) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
    }

    /// Bytes each part would take, for the picker.
    static func size(of folder: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    static func sizes(_ games: [GameEntry]) -> (games: [String: Int64], saves: Int64, states: Int64,
                                                covers: Int64, rtp: Int64, skins: Int64) {
        var perGame: [String: Int64] = [:]
        var saves = size(of: documents.appendingPathComponent("UserData"))
        for game in games {
            perGame[game.id] = size(of: game.folder)
            for save in SaveManager.saves(for: game) where save.url.path.hasPrefix(game.folder.path + "/") {
                saves += Int64((try? save.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
        return (perGame, saves, size(of: support.appendingPathComponent("States")),
                size(of: support.appendingPathComponent("Covers")), size(of: support.appendingPathComponent("RTP")),
                size(of: support.appendingPathComponent("Skins")))
    }

    // MARK: - Restoring

    /// Puts a backup's contents back. Runs off the main thread; reload
    /// the library afterwards.
    static func restore(_ url: URL, keepingGames existing: Set<String>) throws -> Summary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw BackupError.notABackup
        }
        guard archive[manifestName] != nil else { throw BackupError.notABackup }

        let fm = FileManager.default
        let stash = documents.appendingPathComponent("Backups/Restauração \(stamp(Date()))", isDirectory: true)
        var summary = Summary()
        var restoredGames: Set<String> = []

        for entry in archive where entry.type == .file {
            let path = entry.path
            guard !path.contains("../"), !path.hasPrefix("/") else { continue }
            let parts = path.split(separator: "/").map(String.init)
            guard let top = parts.first else { continue }

            let target: URL
            switch top {
            case "Games", "UserData":
                if top == "Games", parts.count >= 3, existing.contains(parts[1]) {
                    // A game already here keeps its files; only saves come back.
                    let name = parts.dropFirst(2).joined(separator: "/")
                    let isSave = SaveManager.isGameFolderSaveName(parts.last ?? "")
                        || name.lowercased().hasPrefix("save data/")
                    guard isSave else { continue }
                }
                if top == "Games", parts.count >= 2 { restoredGames.insert(parts[1]) }
                target = documents.appendingPathComponent(path)
            case "States", "Covers", "RTP", "Skins":
                target = support.appendingPathComponent(path)
            case defaultsName:
                var data = Data()
                _ = try archive.extract(entry) { data.append($0) }
                mergeDefaults(data)
                continue
            default:
                continue
            }

            if fm.fileExists(atPath: target.path) {
                let kept = stash.appendingPathComponent(path)
                try? fm.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: kept)
                try fm.moveItem(at: target, to: kept)
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try archive.extract(entry, to: target)
            summary.files += 1
        }
        summary.games = restoredGames.count
        return summary
    }

    /// Names, profiles, history and covers' bookkeeping come back from
    /// the backup; this device's own settings stay as they are.
    private static func mergeDefaults(_ data: Data) {
        guard let domain = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return }
        let defaults = UserDefaults.standard
        for (key, value) in domain where !key.hasPrefix("settings.") {
            defaults.set(value, forKey: key)
        }
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter.string(from: date)
    }
}
