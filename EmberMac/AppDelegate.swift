import AppKit
import SwiftUI

/// Ember for Mac. Two ways to start:
///
/// - the library (a normal launch): a window with the shelf;
/// - a game: the library opens a new instance of Ember with the link
///   ember-play://play?id=<id>, which shows only that game's window and
///   quits when the game ends. A fresh process per game: the Ruby VM
///   keeps classes between games, so it never runs two.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var libraryWindow: NSWindow?
    private var playing = false
    private var launched = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        launched = true
        // A game's link arrives right around launch: wait one turn of
        // the run loop before deciding this is the library.
        DispatchQueue.main.async { [self] in
            if !playing {
                NSApp.mainMenu = MainMenu.build(playing: false)
                showLibrary()
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.scheme == "ember-play" }),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let id = items.first(where: { $0.name == "id" })?.value else { return }
        // A library already open gets the link only by mistake: it
        // starts the game the usual way, in another instance.
        if libraryWindow != nil {
            if let game = MacLibrary.shared.games.first(where: { $0.id == id }) { MacLibrary.shared.play(game) }
            return
        }
        guard !playing else { return }
        playing = true
        #if DEBUG
        EngineSession.shared.scriptForLaunch = items.first { $0.name == "script" }?.value
        // Development aid: tests run without the game's sound.
        if items.contains(where: { $0.name == "mute" }) { EngineSession.shared.mutedForTest = true }
        #endif
        NSApp.mainMenu = MainMenu.build(playing: true)
        startGame(id, resume: items.contains { $0.name == "resume" })
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// The Dock icon reopens the library.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, !playing { showLibrary() }
        return true
    }

    // MARK: - Library

    private func showLibrary() {
        if let libraryWindow {
            libraryWindow.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Ember"
        window.contentView = NSHostingView(rootView: LibraryWindow().fontDesign(.rounded))
        window.setFrameAutosaveName("EmberLibrary")
        window.minSize = NSSize(width: 720, height: 480)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        libraryWindow = window
        NSApp.activate()
        // An iPhone nearby can send games here.
        MacTransferServer.shared.start()
        #if DEBUG
        developmentHooks()
        #endif
    }

    @objc func importGame(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = String(localized: "Escolha um jogo: .zip, .rar, .7z, .exe ou uma pasta")
        guard panel.runModal() == .OK else { return }
        MacLibrary.shared.importItems(panel.urls)
    }

    // MARK: - Game

    private func startGame(_ id: String, resume: Bool) {
        let folder = GameImporter.gamesFolder.appendingPathComponent(id, isDirectory: true)
        guard let game = GameEntry(folder: folder) else {
            let alert = NSAlert()
            alert.messageText = String(localized: "O jogo não foi encontrado")
            alert.informativeText = id
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let slot = resume && StateStore.autoState(for: id) != nil ? StateStore.autoSlot : nil
        EngineSession.shared.launch(game, resumeSlot: slot)
    }

    @objc func quitGame(_ sender: Any?) {
        EngineSession.shared.quit()
    }

    @objc func saveState(_ sender: Any?) {
        runState("save", slot: StateStore.newSlot())
    }

    @objc func loadLastState(_ sender: Any?) {
        guard let game = EngineSession.shared.currentGame,
              let last = StateStore.states(for: game.id).first else { return }
        runState("load", slot: last.slot)
    }

    @objc func loadState(_ sender: NSMenuItem) {
        guard let slot = sender.representedObject as? String else { return }
        runState("load", slot: slot)
    }

    @objc func setSpeed(_ sender: NSMenuItem) {
        GameSettings.speed = sender.tag
        GameSettings.apply()
    }

    @objc func setFilter(_ sender: NSMenuItem) {
        guard let filter = ScreenFilter(rawValue: sender.tag) else { return }
        ScreenFilter.apply(filter)
    }

    @objc func toggleSound(_ sender: Any?) {
        EngineSession.shared.soundOn.toggle()
    }

    @objc func openCheats(_ sender: Any?) {
        Task { await CheatMenu.open() }
    }

    @objc func takeScreenshot(_ sender: Any?) {
        EngineSession.shared.saveScreenshot { url in
            guard let url else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindow.show()
    }

    private func runState(_ verb: String, slot: String) {
        Task {
            let outcome = await EngineSession.shared.requestState(verb, slot: slot)
            if case .done = outcome { return }
            let alert = NSAlert()
            switch outcome {
            case .busy(let reason): alert.messageText = StateStore.busyText(reason)
            default: alert.messageText = verb == "save"
                ? String(localized: "Não deu para salvar o estado neste jogo")
                : String(localized: "Não deu para carregar o estado")
            }
            alert.runModal()
        }
    }

    // MARK: - Development

    #if DEBUG
    /// EMBER_INSTALL_DEMO=1 installs the demo; EMBER_PLAY=first opens the
    /// first game in its own instance.
    private func developmentHooks() {
        let environment = ProcessInfo.processInfo.environment
        if environment["EMBER_INSTALL_DEMO"] != nil { MacLibrary.shared.installDemo() }
        // EMBER_PLAY=1 opens the first game; EMBER_PLAY=<start of an id>, that one.
        if let wanted = environment["EMBER_PLAY"],
           let game = MacLibrary.shared.games.first(where: { wanted == "1" || $0.id.hasPrefix(wanted) }) {
            MacLibrary.shared.play(game)
        }
    }
    #endif
}

/// The menu bar: App, File (import), Game (while a game plays), View,
/// Window. The Game menu fills its lists (states, speed, filter) each
/// time it opens.
@MainActor
final class MainMenu: NSObject, NSMenuDelegate {
    static let shared = MainMenu()

    static func build(playing: Bool) -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: String(localized: "Sobre o Ember"),
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: String(localized: "Ajustes…"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: String(localized: "Ocultar o Ember"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: String(localized: "Encerrar o Ember"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(app, title: "Ember"))

        if playing {
            let game = NSMenu(title: String(localized: "Jogo"))
            game.delegate = shared
            main.addItem(submenu(game, title: String(localized: "Jogo")))
        } else {
            let file = NSMenu(title: String(localized: "Arquivo"))
            file.addItem(withTitle: String(localized: "Importar jogo…"), action: #selector(AppDelegate.importGame(_:)), keyEquivalent: "o")
            file.addItem(.separator())
            file.addItem(withTitle: String(localized: "Fechar janela"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
            main.addItem(submenu(file, title: String(localized: "Arquivo")))
        }

        let view = NSMenu(title: String(localized: "Visualizar"))
        view.addItem(withTitle: String(localized: "Tela cheia"), action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
            .keyEquivalentModifierMask = [.command, .control]
        main.addItem(submenu(view, title: String(localized: "Visualizar")))

        let window = NSMenu(title: String(localized: "Janela"))
        window.addItem(withTitle: String(localized: "Minimizar"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        main.addItem(submenu(window, title: String(localized: "Janela")))
        NSApp.windowsMenu = window
        return main
    }

    /// The Game menu, built as it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let session = EngineSession.shared
        menu.addItem(withTitle: String(localized: "Salvar estado"), action: #selector(AppDelegate.saveState(_:)), keyEquivalent: "s")
        menu.addItem(withTitle: String(localized: "Carregar o último estado"), action: #selector(AppDelegate.loadLastState(_:)), keyEquivalent: "l")

        let states = NSMenu()
        if let game = session.currentGame {
            for state in StateStore.states(for: game.id).prefix(12) {
                let title = state.isAuto
                    ? String(localized: "Automático · \(state.date.formatted(date: .abbreviated, time: .shortened))")
                    : state.date.formatted(date: .abbreviated, time: .shortened)
                let item = NSMenuItem(title: title, action: #selector(AppDelegate.loadState(_:)), keyEquivalent: "")
                item.representedObject = state.slot
                states.addItem(item)
            }
        }
        if states.items.isEmpty {
            states.addItem(withTitle: String(localized: "Nenhum estado salvo"), action: nil, keyEquivalent: "")
        }
        menu.addItem(Self.submenu(states, title: String(localized: "Estados")))
        menu.addItem(.separator())

        let speed = NSMenu()
        for step in GameSettings.speedSteps {
            let item = NSMenuItem(title: "\(step)x", action: #selector(AppDelegate.setSpeed(_:)), keyEquivalent: "")
            item.tag = step
            item.state = GameSettings.speed == step ? .on : .off
            speed.addItem(item)
        }
        menu.addItem(Self.submenu(speed, title: String(localized: "Velocidade")))

        let filters = NSMenu()
        for filter in ScreenFilter.allCases {
            let item = NSMenuItem(title: filter.title, action: #selector(AppDelegate.setFilter(_:)), keyEquivalent: "")
            item.tag = filter.rawValue
            item.state = ScreenFilter.current == filter ? .on : .off
            item.toolTip = filter.detail
            filters.addItem(item)
        }
        menu.addItem(Self.submenu(filters, title: String(localized: "Filtro")))

        let sound = NSMenuItem(title: String(localized: "Som do jogo"), action: #selector(AppDelegate.toggleSound(_:)), keyEquivalent: "")
        sound.state = session.soundOn ? .on : .off
        menu.addItem(sound)
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Cheats"), action: #selector(AppDelegate.openCheats(_:)), keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "Captura de tela"), action: #selector(AppDelegate.takeScreenshot(_:)), keyEquivalent: "p")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Sair do jogo"), action: #selector(AppDelegate.quitGame(_:)), keyEquivalent: "w")
    }

    static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        return item
    }
}
