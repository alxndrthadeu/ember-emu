import Foundation
import UIKit

/// Pictures of the game's own saves. The save files hold no image, so
/// while a game runs Ember watches its save files; when one is written,
/// the preload script (ember_quicksave.rb) fills the thumbnail with the
/// last quiet map frame it kept (the save screen itself says little).
///
/// Application Support/SaveThumbs/<game id>/<save>@<modified>.png: the
/// modification time in the name ties a picture to one version of the
/// save, so an imported or older save never shows a wrong picture.
enum SaveThumbnails {
    static func folder(for gameID: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("SaveThumbs/\(gameID)", isDirectory: true)
    }

    private static func key(_ save: SaveManager.SaveFile) -> String {
        save.id.replacingOccurrences(of: "/", with: "__")
    }

    private static func url(for save: SaveManager.SaveFile, gameID: String) -> URL {
        let stamp = Int(save.modified.timeIntervalSince1970)
        return folder(for: gameID).appendingPathComponent("\(key(save))@\(stamp).png")
    }

    static func image(for save: SaveManager.SaveFile, gameID: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: save, gameID: gameID).path)
    }

    /// Asks the running game for pictures of these saves (just written).
    static func request(_ saves: [SaveManager.SaveFile], gameID: String) {
        let fm = FileManager.default
        let dir = folder(for: gameID)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var lines: [String] = []
        for save in saves {
            removeOld(of: save, gameID: gameID)
            lines.append(url(for: save, gameID: gameID).path)
        }
        let request = StateStore.folder(for: gameID).appendingPathComponent("thumb_request")
        let previous = (try? String(contentsOf: request, encoding: .utf8)) ?? ""
        try? (previous + lines.joined(separator: "\n") + "\n").write(to: request, atomically: true, encoding: .utf8)
    }

    static func remove(_ save: SaveManager.SaveFile, gameID: String) {
        removeOld(of: save, gameID: gameID)
    }

    private static func removeOld(of save: SaveManager.SaveFile, gameID: String) {
        let dir = folder(for: gameID)
        let prefix = key(save) + "@"
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// "Save1.rxdata" → "Save 1", "Game_2.rxdata" → "Game 2".
    static func displayName(_ save: SaveManager.SaveFile) -> String {
        var name = (save.id as NSString).lastPathComponent
        name = (name as NSString).deletingPathExtension
        name = name.replacingOccurrences(of: "_", with: " ")
        if let range = name.range(of: #"(?<=[A-Za-z])(\d+)$"#, options: .regularExpression) {
            name.replaceSubrange(range, with: " " + String(Int(name[range]) ?? 0))
        }
        return name
    }
}

/// Watches the running game's save files and asks for a picture when
/// one is written. A stat of a few files every two seconds.
@MainActor
final class SaveWatcher {
    private var timer: Timer?
    private var known: [String: Date]?
    private var game: GameEntry?

    func start(_ game: GameEntry) {
        stop()
        self.game = game
        known = nil
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        game = nil
        known = nil
    }

    private func scan() {
        guard let game else { return }
        let saves = SaveManager.saves(for: game)
        let now = Dictionary(saves.map { ($0.id, $0.modified) }, uniquingKeysWith: { a, _ in a })
        if let known {
            let written = saves.filter { known[$0.id] != $0.modified }
            if !written.isEmpty {
                SaveThumbnails.request(written, gameID: game.id)
            }
        }
        known = now
    }
}
