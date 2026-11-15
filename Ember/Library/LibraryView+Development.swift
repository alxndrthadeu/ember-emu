import SwiftUI

#if DEBUG
extension LibraryView {
    /// Development aids, so the simulator can be driven from the
    /// command line:
    ///   EMBER_IMPORT=<path>       imports a .zip or folder at launch
    ///   EMBER_AUTOLAUNCH=<id>     starts that game ("first" = any)
    ///   EMBER_AUTOQUIT=<seconds>  then quits it, as the menu's Sair does
    ///   EMBER_AUTOREOPEN=1        then taps the game again
    ///   EMBER_AUTOMENU=<seconds>  opens the in-game menu (ControlsOverlay)
    ///   EMBER_SHOW=history|controls|options|saves|gamecontrols|import  opens that screen
    ///   EMBER_GAME=<id>           the game EMBER_SHOW opens (default: the first)
    ///   EMBER_KEYS="3:enter,1:down,2:save:t1,2:load:t1,1:snap"  drives the
    ///   game: wait N seconds, then press a key / save or load a state
    ///   EMBER_RESUME=1            starts from the auto state
    ///   EMBER_IMPORT_SAVES=<path>[:<path>…]  imports saves into the first game
    ///   EMBER_EXPORT_SAVES=1      exports the first game's saves (logs the .zip)
    ///   EMBER_WIFI=1              turns on the Wi-Fi transfer (logs the address)
    ///   EMBER_INSTALL_DEMO=1      copies the bundled demo game into the library
    ///   EMBER_SHARE_SAVES=<id>    builds that game's .embersave (logs the path)
    ///   EMBER_QUICK=continue|import|wifi  acts as an app icon quick action
    ///   EMBER_TV=1                starts "Jogar na TV" 8 s after the game opens
    ///   EMBER_MAKE_BACKUP=<id>    writes a backup with that whole game (logs the path)
    ///   EMBER_ARCHIVE=<id> / EMBER_UNARCHIVE=<id>  archives or brings back a game
    ///   EMBER_FAKE_CLOUD=1        a local folder stands in for iCloud
    ///   EMBER_DUMP_SCRIPTS=<id>   writes the game's script text to tmp (logs the path)
    func developmentHooks() {
        let environment = ProcessInfo.processInfo.environment
        if let paths = environment["EMBER_IMPORT"] {
            library.importItems(paths.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
        }
        if let game = library.games.first {
            if let paths = environment["EMBER_IMPORT_SAVES"] {
                let urls = paths.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
                print("[ember-saves] import:", Result { try SaveManager.importSaves(from: urls, into: game) })
            }
            if environment["EMBER_EXPORT_SAVES"] != nil {
                print("[ember-saves] export:", Result { try SaveManager.export(game) })
            }
        }
        if let id = environment["EMBER_SHARE_SAVES"], let game = library.games.first(where: { $0.id == id }) {
            print("[ember-share]", Result { try SaveShare.package(game) })
        }
        if let id = environment["EMBER_MAKE_BACKUP"] {
            var options = EmberBackup.Options()
            options.games = [id]
            print("[ember-backup]", Result { try EmberBackup.make(options, library: library.games) })
        }
        if let id = environment["EMBER_ARCHIVE"] {
            Task {
                try? await Task.sleep(for: .seconds(5))
                if let game = library.games.first(where: { $0.id == id }) { library.archive(game) }
            }
        }
        if let id = environment["EMBER_UNARCHIVE"] {
            Task {
                try? await Task.sleep(for: .seconds(5))
                if let record = library.archived.first(where: { $0.id == id }) { library.unarchive(record) }
            }
        }
        if let id = environment["EMBER_DUMP_SCRIPTS"], let game = library.games.first(where: { $0.id == id }) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(id)-scripts.rb")
            try? ScriptScanner.scripts(in: game.folder).write(to: url, atomically: true, encoding: .utf8)
            print("[ember-scripts]", url.path, GameKeyScanner.keys(inCode: ScriptScanner.scripts(in: game.folder)).map(\.name))
        }
        if let quick = environment["EMBER_QUICK"] {
            let map: [String: QuickAction] = ["continue": .continueLast, "import": .importGame, "wifi": .wifi]
            AppRouter.shared.quickAction = map[quick]
        }
        if environment["EMBER_INSTALL_DEMO"] != nil {
            library.installDemo()
        }
        if environment["EMBER_WIFI"] != nil {
            WifiTransfer.shared.start()
            Task {
                try? await Task.sleep(for: .seconds(1))
                print("[ember-wifi]", WifiTransfer.shared.address ?? "no address")
            }
        }
        switch environment["EMBER_SHOW"] {
        case "history": showingHistory = true
        case "controls": showingControls = true
        case "options", "saves", "gamecontrols":
            let id = environment["EMBER_GAME"]
            optionsFor = library.games.first { id == nil || $0.id == id }
        case "controller": library.chooseController = library.games.first
        case "import", "computer", "rtp": AppRouter.shared.tab = .importGames
        case "settings", "profiles": AppRouter.shared.tab = .settings
        default: break
        }
        guard let id = environment["EMBER_AUTOLAUNCH"],
              let game = library.games.first(where: { $0.id == id || id == "first" })
        else { return }
        let resume = environment["EMBER_RESUME"] != nil ? StateStore.autoSlot : nil
        session.launch(game, resumeSlot: resume)
        if environment["EMBER_TV"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(8))
                TVStream.shared.start()
                try? await Task.sleep(for: .seconds(1))
                print("[ember-tv]", TVStream.shared.address ?? "no address", TVStream.shared.isOn)
            }
        }
        if let script = environment["EMBER_KEYS"] {
            Task { await runKeyScript(script) }
        }
        if let seconds = environment["EMBER_AUTOQUIT"].flatMap(Double.init) {
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                session.quit()
                if environment["EMBER_AUTOREOPEN"] != nil {
                    try? await Task.sleep(for: .seconds(2))
                    open(game)
                }
            }
        }
    }
}

/// Development aid behind EMBER_KEYS: steps of "seconds:action".
@MainActor
private func runKeyScript(_ script: String) async {
    let keys: [String: GameKey] = ["enter": .confirm, "esc": .back, "shift": .start, "up": .up,
                                   "down": .down, "left": .left, "right": .right]
    for step in script.split(separator: ",") {
        let parts = step.split(separator: ":").map(String.init)
        guard let seconds = Double(parts.first ?? "") , parts.count >= 2 else { continue }
        try? await Task.sleep(for: .seconds(seconds))
        switch parts[1] {
        case "save", "load":
            let slot = parts.count > 2 ? parts[2] : StateStore.autoSlot
            let outcome = await EngineSession.shared.requestState(parts[1], slot: slot)
            print("[ember-keys] \(parts[1]) \(slot): \(outcome)")
        case "cheat":
            // As the Cheats tile in the game menu does.
            await CheatMenu.open()
            print("[ember-keys] cheat")
        default:
            if let key = keys[parts[1]] {
                key.press()
                try? await Task.sleep(for: .milliseconds(90))
                key.release()
            } else if parts[1].count == 1, let character = parts[1].first {
                KeyTapper.type(character)
            }
            print("[ember-keys] \(parts[1])")
        }
    }
}
#else
extension LibraryView {
    func developmentHooks() {}
}
#endif
