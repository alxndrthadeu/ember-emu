import Foundation

/// The per-session config overlay Ember lays over a game's mkxp.json
/// (mkxp_setConfigOverlayJSON). The overlay replaces whole top-level
/// keys, so a key the game also sets is merged here first.
enum EngineConfig {
    /// Ember's own preload scripts, run before the game's scripts.
    ///
    /// ember_quicksave is a preload, not a postload: the engine runs a
    /// config postloadScript only from rgss_main, which only VX Ace games
    /// call. The script hooks game classes lazily, once they exist.
    private static var emberPreloads: [String] { scripts(["ember_quiet_warnings", "ember_quicksave"]) }
    private static var emberPostloads: [String] { [] }

    private static func scripts(_ names: [String]) -> [String] {
        names.compactMap { Bundle.main.url(forResource: $0, withExtension: "rb")?.path }
    }

    static func apply(for game: GameEntry) {
        let gameConfig = readGameConfig(in: game.folder)
        let gamePreloads = gameConfig["preloadScript"] as? [String] ?? []
        let gamePostloads = gameConfig["postloadScript"] as? [String] ?? []
        var overlay: [String: Any] = ["preloadScript": gamePreloads + emberPreloads,
                                      "postloadScript": gamePostloads + emberPostloads]
        // The player's screen filter.
        overlay.merge(ScreenFilter.overlay) { _, ember in ember }
        // MIDI instruments, unless the game brings its own soundfont.
        if (gameConfig["midiSoundFont"] as? String ?? "").isEmpty,
           let soundFont = Bundle.main.url(forResource: "GeneralUser-GS", withExtension: "sf2") {
            overlay["midiSoundFont"] = soundFont.path
        }
        // The imported RTP of the game's version, after any the game
        // lists itself: the game's own files always win.
        if let rtp = RTPStore.path(forRGSS: GameFolder.rgssVersion(in: game.folder)) {
            overlay["RTP"] = (gameConfig["RTP"] as? [String] ?? []) + [rtp]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: overlay),
              let json = String(data: data, encoding: .utf8)
        else { return }
        mkxp_setConfigOverlayJSON(json)
    }

    /// The game's mkxp.json, which may hold // and /* */ comments.
    private static func readGameConfig(in folder: URL) -> [String: Any] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        guard let name = names.first(where: { $0.lowercased() == "mkxp.json" }),
              let text = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8),
              let data = stripComments(text).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed]) as? [String: Any]
        else { return [:] }
        return object
    }

    /// Removes // and /* */ comments outside strings.
    private static func stripComments(_ text: String) -> String {
        var out = ""
        var chars = Array(text)
        var i = 0
        var inString = false
        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if inString {
                out.append(c)
                if c == "\\", let next { out.append(next); i += 2; continue }
                if c == "\"" { inString = false }
                i += 1
            } else if c == "\"" {
                inString = true
                out.append(c)
                i += 1
            } else if c == "/", next == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
            } else if c == "/", next == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
            } else {
                out.append(c)
                i += 1
            }
        }
        chars = []
        return out
    }
}
