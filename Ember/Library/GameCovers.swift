import Foundation
import UIKit

/// Where a game's cover comes from, in order:
///
/// 1. A picture the player chose (Fotos).
/// 2. The game's own title image (Graphics/Titles), when its files
///    are loose.
/// 3. The last frame the engine captured when the game paused (menu
///    opened, app sent to the background). Packed games, like Pokémon
///    Flux with its .fpk archives, only ever get this one.
///
/// Covers live in Application Support, never in the game's folders:
/// UserData holds the game's own saves.
enum GameCovers {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "bmp"]

    static func url(forGameID id: String, folder: URL) -> URL? {
        let fm = FileManager.default
        let custom = customURL(forGameID: id)
        if fm.fileExists(atPath: custom.path) { return custom }
        if let title = titleImage(in: folder) { return title }
        let snapshot = snapshotURL(forGameID: id)
        return fm.fileExists(atPath: snapshot.path) ? snapshot : nil
    }

    static func hasCustomCover(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: customURL(forGameID: id).path)
    }

    /// Saves a paused frame as the automatic cover, off the main thread.
    static func saveSnapshot(_ image: UIImage, forGameID id: String) {
        write(image, to: snapshotURL(forGameID: id))
    }

    static func setCustomCover(_ image: UIImage, forGameID id: String) {
        write(image, to: customURL(forGameID: id), async: false)
    }

    static func removeCustomCover(forGameID id: String) {
        try? FileManager.default.removeItem(at: customURL(forGameID: id))
    }

    /// Covers written by earlier builds sat in UserData, next to the
    /// saves. Move them out.
    static func migrateLegacyCover(forGameID id: String) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let legacy = documents.appendingPathComponent("UserData/\(id)/cover.jpg")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        let target = snapshotURL(forGameID: id)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.removeItem(at: legacy)
        } else {
            try? FileManager.default.moveItem(at: legacy, to: target)
        }
    }

    // MARK: Files

    private static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Covers", isDirectory: true)
    }

    private static func snapshotURL(forGameID id: String) -> URL {
        folder.appendingPathComponent("\(id).jpg")
    }

    private static func customURL(forGameID id: String) -> URL {
        folder.appendingPathComponent("\(id)-custom.jpg")
    }

    private static func write(_ image: UIImage, to url: URL, async: Bool = true) {
        let work = {
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        if async {
            DispatchQueue.global(qos: .utility).async(execute: work)
        } else {
            work()
        }
    }

    /// The first image in Graphics/Titles. Windows games mix the case
    /// of folder names, so the lookup ignores case.
    private static func titleImage(in folder: URL) -> URL? {
        guard let graphics = child(of: folder, named: "Graphics"),
              let titles = child(of: graphics, named: "Titles")
        else { return nil }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: titles.path)) ?? []
        return names
            .filter { imageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .first
            .map { titles.appendingPathComponent($0) }
    }

    private static func child(of folder: URL, named name: String) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.first { $0.caseInsensitiveCompare(name) == .orderedSame }
            .map { folder.appendingPathComponent($0) }
    }
}

/// One stretch of play, for the history.
struct PlaySession: Codable, Identifiable, Hashable {
    let id: UUID
    let gameID: String
    var title: String
    let start: Date
    var end: Date

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

/// Every session played, newest first, and the last time each game ran.
enum PlayHistory {
    private static let sessionsKey = "history.sessions"
    private static let legacyKey = "library.lastPlayed"
    private static let limit = 500

    static var sessions: [PlaySession] {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              let sessions = try? JSONDecoder().decode([PlaySession].self, from: data)
        else { return [] }
        return sessions
    }

    static func lastPlayed(_ id: String) -> Date? {
        let fromSessions = sessions.first { $0.gameID == id }?.end
        let legacy = (UserDefaults.standard.dictionary(forKey: legacyKey) as? [String: Double])?[id]
            .map(Date.init(timeIntervalSince1970:))
        return [fromSessions, legacy].compactMap { $0 }.max()
    }

    static func totalTime(_ id: String) -> TimeInterval {
        sessions.filter { $0.gameID == id }.reduce(0) { $0 + $1.duration }
    }

    /// Starts a session. Returns its id, for `touch`.
    static func begin(gameID: String, title: String) -> UUID {
        let now = Date()
        let session = PlaySession(id: UUID(), gameID: gameID, title: title, start: now, end: now)
        save([session] + sessions)
        return session.id
    }

    /// Moves the session's end to now. Called while the game runs, so
    /// a session cut short by the system still counts.
    static func touch(_ id: UUID) {
        var all = sessions
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].end = Date()
        save(all)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: sessionsKey)
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }

    private static func save(_ sessions: [PlaySession]) {
        let trimmed = Array(sessions.prefix(limit))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }
}

/// Names the player gave to games. The folder keeps its name, so the
/// saves stay where they are.
enum TitleOverrides {
    private static let key = "library.customTitles"

    static func title(for id: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?[id]
    }

    static func set(_ title: String?, for id: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        all[id] = trimmed.isEmpty ? nil : trimmed
        UserDefaults.standard.set(all, forKey: key)
    }
}

/// The Ruby the player chose for a game, overriding detection.
enum RubyChoice: String, CaseIterable, Identifiable {
    case ruby18 = "18"
    case ruby19 = "19"
    case ruby31 = "31"

    var id: String { rawValue }

    var version: MKXPRubyVersion {
        switch self {
        case .ruby18: MKXP_RUBY_18
        case .ruby19: MKXP_RUBY_19
        case .ruby31: MKXP_RUBY_31
        }
    }

    var label: String {
        switch self {
        case .ruby18: "1.8"
        case .ruby19: "1.9"
        case .ruby31: "3.1"
        }
    }

    static func label(for version: MKXPRubyVersion) -> String {
        allCases.first { $0.version == version }?.label ?? "3.1"
    }

    private static let key = "library.rubyChoice"

    static func saved(for id: String) -> RubyChoice? {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?[id].flatMap(RubyChoice.init(rawValue:))
    }

    static func set(_ choice: RubyChoice?, for id: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        all[id] = choice?.rawValue
        UserDefaults.standard.set(all, forKey: key)
    }
}

/// Games where the player turned on the game's own keyboard scene for
/// name entry (mkxp_setUseInGameKeyboard).
enum InGameKeyboard {
    private static let key = "library.inGameKeyboard"

    static func isOn(for id: String) -> Bool {
        (UserDefaults.standard.dictionary(forKey: key) as? [String: Bool])?[id] ?? false
    }

    static func set(_ on: Bool, for id: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: Bool] ?? [:]
        all[id] = on ? true : nil
        UserDefaults.standard.set(all, forKey: key)
    }
}
