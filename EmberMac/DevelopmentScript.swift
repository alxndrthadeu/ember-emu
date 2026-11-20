#if DEBUG
import AppKit

/// Development aid: drives a game instance from the ember-play link's
/// `script` (the library passes EMBER_SCRIPT through it). Steps of
/// "seconds:action", as EMBER_KEYS on iPhone:
///   enter, esc, up, down, left, right, shift  a key tap
///   save:<slot>, load:<slot>                   a save state
///   cover, shot                                cover or screenshot
///   restart                                    the game from its title
///   quit                                       ends the game
@MainActor
enum DevelopmentScript {
    static func run(_ script: String?) {
        guard let script, !script.isEmpty else { return }
        Task { @MainActor in
            for step in script.split(separator: ",") {
                let parts = step.split(separator: ":", maxSplits: 2).map(String.init)
                guard parts.count >= 2, let seconds = Double(parts[0]) else { continue }
                try? await Task.sleep(for: .seconds(seconds))
                perform(parts[1], argument: parts.count > 2 ? parts[2] : nil)
            }
        }
    }

    private static func perform(_ action: String, argument: String?) {
        let keys: [String: GameKey] = ["enter": .confirm, "esc": .back, "up": .up, "down": .down,
                                       "left": .left, "right": .right, "shift": .start]
        if let key = keys[action] {
            KeyTapper.tap(key)
            print("[ember-script] \(action)")
            return
        }
        switch action {
        case "save", "load":
            Task {
                let outcome = await EngineSession.shared.requestState(action, slot: argument ?? "dev")
                print("[ember-script] \(action) \(argument ?? "dev"): \(outcome)")
            }
        case "cover":
            EngineSession.shared.saveCover()
        case "shot":
            EngineSession.shared.saveScreenshot { print("[ember-script] shot \($0?.path ?? "failed")") }
        case "restart":
            EngineSession.shared.restart()
            print("[ember-script] restart")
        case "quit":
            EngineSession.shared.quit()
        default:
            break
        }
    }
}
#endif
