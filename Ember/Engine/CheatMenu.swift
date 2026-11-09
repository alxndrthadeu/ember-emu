import Foundation

/// The engine's cheat menus (level, money, items; heal and walk through
/// walls in Essentials), opened from Ember's game menu. They open on
/// Input::HOME on the map, with cheats on.
@MainActor
enum CheatMenu {
    static func open() async {
        guard let game = EngineSession.shared.currentGame else { return }
        mkxp_setCheatsEnabled(true)
        // ember_quicksave.rb loads the menu first if the engine did not
        // (it checks every few frames).
        let request = StateStore.folder(for: game.id).appendingPathComponent("cheat_request")
        try? Data().write(to: request)
        try? await Task.sleep(for: .milliseconds(400))
        GameLog.shared.note("menu de cheats")
        KeyTapper.tap(.home)
    }
}
