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

    @objc func cycleSpeed(_ sender: Any?) {
        let steps = GameSettings.speedSteps
        GameSettings.speed = steps[((steps.firstIndex(of: GameSettings.speed) ?? 0) + 1) % steps.count]
        GameSettings.apply()
        if let item = sender as? NSMenuItem { item.title = MainMenu.speedTitle }
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
        if environment["EMBER_PLAY"] != nil, let first = MacLibrary.shared.games.first {
            MacLibrary.shared.play(first)
        }
    }
    #endif
}

/// The menu bar: App, File (import), Game (while a game plays), Window.
enum MainMenu {
    @MainActor
    static var speedTitle: String {
        String(localized: "Velocidade: \(GameSettings.speed)x")
    }

    @MainActor
    static func build(playing: Bool) -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: String(localized: "Sobre o Ember"),
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: String(localized: "Ocultar o Ember"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: String(localized: "Encerrar o Ember"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(app, title: "Ember"))

        if playing {
            let game = NSMenu(title: String(localized: "Jogo"))
            game.addItem(withTitle: String(localized: "Salvar estado"), action: #selector(AppDelegate.saveState(_:)), keyEquivalent: "s")
            game.addItem(withTitle: String(localized: "Carregar o último estado"), action: #selector(AppDelegate.loadLastState(_:)), keyEquivalent: "l")
            game.addItem(.separator())
            game.addItem(withTitle: speedTitle, action: #selector(AppDelegate.cycleSpeed(_:)), keyEquivalent: "")
            game.addItem(.separator())
            game.addItem(withTitle: String(localized: "Sair do jogo"), action: #selector(AppDelegate.quitGame(_:)), keyEquivalent: "w")
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

    private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        return item
    }
}
