import SwiftUI
import UIKit

/// Starts the engine for one game and puts Ember's controls on top of
/// the game window.
///
/// Phase 0 limit: one game per app launch. The engine keeps Ruby and
/// SDL state for the life of the process, so a second mkxp_run_app in
/// the same process is not safe. Phase 1 moves each game into its own
/// process, the way Empo does with ExtensionKit.
@MainActor
final class EngineSession: ObservableObject {
    static let shared = EngineSession()

    enum State: Equatable {
        case idle
        case preparing(String)
        case running
        case finished
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// The game being played, from launch to the end of the session.
    @Published private(set) var currentGame: GameEntry?

    /// The library window, shown again when the game ends.
    weak var launcherWindow: UIWindow?

    private var gameScreen: GameViewController?
    private var libraryRoot: UIViewController?
    private var windowWatcher: Timer?

    private init() {
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { EngineSession.shared.appWillResignActive() }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { EngineSession.shared.appDidBecomeActive() }
        }
    }

    // MARK: - Background

    // MARK: - History

    private var sessionID: UUID?
    private var resumeSlotForLog: String?
    private var historyTimer: Timer?

    private func touchSession() {
        if let sessionID { PlayHistory.touch(sessionID) }
    }

    /// True while the game is paused because the app left the screen.
    private var pausedForBackground = false

    /// The game pauses when the app leaves the screen, as in Manic EMU.
    /// The pause also captures the frame that becomes the cover.
    /// Leaving the screen: save the "auto" state (the game does it at
    /// its next quiet frame), then pause. iOS may close a suspended app
    /// to free memory; "Continuar" then resumes from this state.
    private func appWillResignActive() {
        touchSession()
        guard state == .running, let game = currentGame,
              !mkxp_isPaused(), !mkxp_isPauseRequested() else { return }
        GameLog.shared.note("o app saiu da tela")
        pausedForBackground = AppSettings.pauseOnBackground
        let task = UIApplication.shared.beginBackgroundTask(withName: "ember.autostate")
        Task { @MainActor in
            _ = await StateStore.request("save", slot: StateStore.autoSlot, gameID: game.id, timeout: 1.5)
            if self.pausedForBackground, self.state == .running { mkxp_requestPause() }
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    // MARK: - Save states

    /// Saves or loads a state in the running game. The game must not be
    /// paused: callers close the menu first.
    func requestState(_ verb: String, slot: String) async -> StateStore.Outcome {
        guard state == .running, let game = currentGame else { return .noAnswer }
        let outcome = await StateStore.request(verb, slot: slot, gameID: game.id)
        GameLog.shared.note("estado \(verb == "save" ? "salvo" : "carregado") (\(slot)): \(outcome)")
        return outcome
    }

    private func appDidBecomeActive() {
        guard pausedForBackground else { return }
        GameLog.shared.note("o app voltou")
        pausedForBackground = false
        mkxp_requestResume()
    }

    /// `resumeSlot`: open the game straight into that save state
    /// (StateStore), skipping its title screen when the game allows.
    func launch(_ game: GameEntry, resumeSlot: String? = nil) {
        guard state == .idle else { return }
        resumeSlotForLog = resumeSlot
        state = .preparing(game.title)
        StateStore.prepareEnvironment(gameID: game.id, resumeSlot: resumeSlot)
        // Games live in Documents/Games, which is writable: the engine
        // runs them in place (it writes a path cache next to them).
        start(game, in: game.folder)
    }

    // MARK: - Engine

    private func start(_ game: GameEntry, in folder: URL) {
        let resources = Bundle.main.resourceURL!
        let userData = GameStorage.userDataFolder(for: game)

        mkxp_setActiveRubyVersion(game.rubyVersion)
        EngineConfig.apply(for: game)
        // Buttons, on screen and on controllers, follow the game's profile.
        ControlMapper.shared.profile = ProfileStore.shared.profile(for: game)
        PhysicalControllerInput.shared.start()
        ResourceMonitor.startIfRequested()
        PerformanceModel.shared.start()
        GameLog.shared.begin(game: game, details: [
            "Ruby: \(RubyChoice.label(for: game.rubyVersion))\(RubyChoice.saved(for: game.id) == nil ? " (automático)" : "")",
            "Skin: \(SkinStore.shared.current.name) · Controles: \(ControlMapper.shared.profile.name)",
            "Retomar: \(resumeSlotForLog ?? "não")",
        ])
        // The game's own on-screen keyboard for name entry, when the
        // player turned it on for this game.
        mkxp_setUseInGameKeyboard(InGameKeyboard.isOn(for: game.id))
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        mkxp_setLauncherIdentity("Ember", version)
        mkxp_setUserDataDirectory(userData.path)
        mkxp_setSharedFontsDirectory(resources.appendingPathComponent("Assets.bundle/Fonts").path)
        mkxp_setCABundlePath(resources.appendingPathComponent("Assets.bundle/cacert.pem").path)
        // The engine reads mkxp.json from here, not from the working
        // directory.
        mkxp_setManagedConfigDir(folder.path)
        // Ember shows its own keyboard (GameTextField). SDL reads its
        // hints from the environment.
        setenv("SDL_ENABLE_SCREEN_KEYBOARD", "0", 1)
        // Set before the engine starts, so mkxp_waitForGamePath
        // returns at once.
        mkxp_setGamePath(folder.path)

        // Ember's window shows the game screen from now on. SDL's view
        // moves in when the engine creates it.
        let gameScreen = GameViewController()
        self.gameScreen = gameScreen
        libraryRoot = launcherWindow?.rootViewController
        launcherWindow?.rootViewController = gameScreen
        // The game screen is dark in both modes, sheets included, and
        // sheets take their style from the window.
        launcherWindow?.overrideUserInterfaceStyle = .dark

        currentGame = game
        sessionID = PlayHistory.begin(gameID: game.id, title: game.title)
        historyTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { EngineSession.shared.touchSession() }
        }
        GameLayout.shared.observeEngine()
        observeMessages()
        PauseSnapshot.shared.observeEngine()
        observeTextInput()
        GameSettings.apply()
        state = .running
        watchForGameWindow()

        // Not a main-queue block: EmberRunEngine holds the main thread
        // until the game ends (see EmberEngine.h).
        RunLoop.main.perform {
            _ = EmberRunEngine()
            MainActor.assumeIsolated { self.engineDidEnd() }
        }
    }

    private func engineDidEnd() {
        GameLog.shared.note("o jogo terminou")
        GameLog.shared.end()
        PerformanceModel.shared.stop()
        PhysicalControllerInput.shared.stop()
        touchSession()
        historyTimer?.invalidate()
        historyTimer = nil
        sessionID = nil
        windowWatcher?.invalidate()
        windowWatcher = nil
        gameScreen = nil
        if let libraryRoot {
            launcherWindow?.rootViewController = libraryRoot
        }
        libraryRoot = nil
        launcherWindow?.overrideUserInterfaceStyle = .unspecified
        currentGame = nil
        // New cover and "Continuar".
        LibraryStore.shared.reload()
        state = .finished
        launcherWindow?.makeKeyAndVisible()
    }

    /// Ends the game. The engine stops at its next frame (also when
    /// paused), mkxp_run_app returns, and engineDidEnd brings the
    /// library back.
    func openKeyboard() {
        gameScreen?.openKeyboard()
    }

    func quit() {
        guard state == .running else { return }
        mkxp_requestTerminate()
    }

    // MARK: - Errors and notices

    /// The engine reports a script error, or a game's own msgbox, and
    /// blocks its thread until the player dismisses it. Without these
    /// handlers the game freezes on its first error.
    private func observeMessages() {
        mkxp_setErrorMessageCallback({ message, _ in
            let text = message.map { String(cString: $0) } ?? ""
            DispatchQueue.main.async {
                MainActor.assumeIsolated { EngineSession.shared.presentEngineMessage(text, isError: true) }
            }
        }, nil)
        mkxp_setInfoMessageCallback({ message, _ in
            let text = message.map { String(cString: $0) } ?? ""
            DispatchQueue.main.async {
                MainActor.assumeIsolated { EngineSession.shared.presentEngineMessage(text, isError: false) }
            }
        }, nil)
    }

    private func presentEngineMessage(_ text: String, isError: Bool) {
        guard let screen = gameScreen, !text.isEmpty else {
            isError ? mkxp_signalErrorDismissed() : mkxp_signalInfoDismissed()
            return
        }
        if isError {
            GameLog.shared.error(text)
        } else {
            GameLog.shared.note("aviso do jogo: \(text)")
        }
        let shown = text.count > 900 ? String(text.prefix(900)) + "…" : text
        let alert: UIAlertController
        if isError {
            let title = currentGame.map { "\($0.title) encontrou um erro" } ?? "O jogo encontrou um erro"
            let hint = "\n\nSe o jogo não abre, tente outra versão do Ruby: segure o jogo na biblioteca e toque em Ruby."
            alert = UIAlertController(title: title, message: shown + hint, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Copiar erro", style: .default) { _ in
                UIPasteboard.general.string = text
                mkxp_signalErrorDismissed()
            })
            alert.addAction(UIAlertAction(title: "Fechar", style: .cancel) { _ in
                mkxp_signalErrorDismissed()
            })
        } else {
            alert = UIAlertController(title: currentGame?.title, message: shown, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                mkxp_signalInfoDismissed()
            })
        }
        var top: UIViewController = screen
        while let presented = top.presentedViewController { top = presented }
        top.present(alert, animated: true)
    }

    // MARK: - Text input

    /// The engine fires this on its own thread when a game turns text
    /// input on or off (`Input.text_input`).
    private func observeTextInput() {
        mkxp_setTextInputModeCallback({ active, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    EngineSession.shared.gameScreen?.setTextInputActive(active != 0)
                }
            }
        }, nil)
    }

    // MARK: - Game view

    /// SDL creates its window once the engine is up. The engine pumps
    /// the main run loop, so a timer still fires while it runs.
    private func watchForGameWindow() {
        windowWatcher = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            MainActor.assumeIsolated {
                guard let pointer = mkxp_getGameWindow(), let gameScreen = self.gameScreen else { return }
                let window = Unmanaged<UIWindow>.fromOpaque(pointer).takeUnretainedValue()
                guard gameScreen.adopt(gameWindow: window) else { return }
                timer.invalidate()
                self.windowWatcher = nil
            }
        }
    }
}

/// Where a game's files live while it runs.
enum GameStorage {
    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Saves and settings, kept apart from the game files so a game
    /// can be replaced without losing them.
    static func userDataFolder(for game: GameEntry) -> URL {
        let folder = documents.appendingPathComponent("UserData/\(game.id)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
