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
@Observable
final class EngineSession {
    static let shared = EngineSession()

    enum State: Equatable {
        case idle
        case preparing(String)
        case running
        case finished
        case failed(String)
    }

    private(set) var state: State = .idle
    /// The game being played, from launch to the end of the session.
    private(set) var currentGame: GameEntry?

    /// The library window, shown again when the game ends.
    @ObservationIgnored weak var launcherWindow: UIWindow?

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
    /// Pictures for the game's own saves as they are written.
    private let saveWatcher = SaveWatcher()

    private func touchSession() {
        // Rewrites the history list: off the main thread, the game's.
        if let sessionID { Task.detached(priority: .utility) { PlayHistory.touch(sessionID) } }
    }

    /// True while the game is paused because the app left the screen.
    private var pausedForBackground = false

    /// The game pauses when the app leaves the screen, as in Manic EMU.
    /// The pause also captures the frame that becomes the cover.
    /// Leaving the screen: save the "auto" state (the game does it at
    /// its next quiet frame), then pause. iOS may close a suspended app
    /// to free memory; "Continuar" then resumes from this state.
    /// Then what the game saved (and that state) goes to iCloud, in the
    /// time iOS gives an app on its way out: a save made just before
    /// leaving does not wait for the next time Ember opens. Once in the
    /// iCloud folder, iOS uploads it even with Ember closed.
    private func appWillResignActive() {
        touchSession()
        guard state == .running, let game = currentGame else { return }
        let task = UIApplication.shared.beginBackgroundTask(withName: "ember.leaving")
        let playing = !mkxp_isPaused() && !mkxp_isPauseRequested()
        if playing {
            GameLog.shared.note("o app saiu da tela")
            pausedForBackground = AppSettings.pauseOnBackground
        }
        Task { @MainActor in
            if playing {
                _ = await StateStore.request("save", slot: StateStore.autoSlot, gameID: game.id, timeout: 1.5)
                if self.pausedForBackground, self.state == .running { mkxp_requestPause() }
            }
            if SaveSync.syncsAutomatically(game.id) {
                let folders = SaveSync.GameFolders(game)
                let report = await Task.detached(priority: .userInitiated) { SaveSync.upload(folders) }.value
                SyncStatus.shared.finished(report, titles: [game.id: game.title])
                if report.uploaded > 0 { GameLog.shared.note("saindo da tela: \(report.uploaded) arquivo(s) enviados ao iCloud") }
            }
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
        if verb == "save", case .done = outcome {
            // The state goes to iCloud now; the automatic one quietly.
            Task {
                if await SyncStatus.shared.uploadWhilePlaying(game), slot != StateStore.autoSlot {
                    SyncStatus.shared.show(String(localized: "Estado salvo no iCloud"))
                }
            }
        }
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
        GameAudio.shared.configureSession()
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
        // A save the game writes goes to iCloud as soon as it is done;
        // iCloud gets ready now, not at the first save.
        SaveSync.prepare()
        saveWatcher.onSaved = { game in
            Task {
                if await SyncStatus.shared.uploadWhilePlaying(game) {
                    SyncStatus.shared.show(String(localized: "Save no iCloud"))
                }
            }
        }
        saveWatcher.start(game)
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
        saveWatcher.stop()
        sessionID = nil
        windowWatcher?.invalidate()
        windowWatcher = nil
        gameScreen = nil
        TVStream.shared.stop()
        GameLayout.shared.onTV = false
        if let libraryRoot {
            launcherWindow?.rootViewController = libraryRoot
        }
        libraryRoot = nil
        launcherWindow?.overrideUserInterfaceStyle = .unspecified
        currentGame = nil
        // New cover and "Continuar".
        LibraryStore.shared.reload()
        state = .finished
        // What the game saved goes to iCloud, and the player hears so.
        LibraryStore.shared.syncSaves(announce: true)
        launcherWindow?.makeKeyAndVisible()
    }

    /// Ends the game. The engine stops at its next frame (also when
    /// paused), mkxp_run_app returns, and engineDidEnd brings the
    /// library back.
    func openKeyboard() {
        gameScreen?.openKeyboard()
    }

    /// The system keyboard is up (a name being typed).
    var isTyping: Bool {
        gameScreen?.isTyping ?? false
    }

    func quit() {
        guard state == .running else { return }
        mkxp_requestTerminate()
    }

    // MARK: - Errors and notices

    /// The engine reports a script error, or a game's own msgbox, and
    /// blocks its thread until the player dismisses it. Without these
    /// handlers the game freezes on its first error.
    /// Nonisolated: the engine calls these closures on its own thread
    /// (Swift 6 would trap a main-actor closure there).
    nonisolated private func observeMessages() {
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

    /// Set when the player switched Ruby from an error: the library
    /// says the game opens with it next time.
    var rubyChangedAfterError: String?

    /// The Ruby to try next when an error looks like a version mismatch
    /// (syntax only one Ruby reads, String methods that changed between
    /// 1.8 and 1.9+, frozen strings in 3.1). Nil for other errors.
    static func rubySuggestion(for text: String, game: GameEntry) -> RubyChoice? {
        let signatures = ["SyntaxError", "syntax error", "invalid multibyte char", "undefined method `getc'",
                          "undefined method `each' for", "can't modify frozen String", "FrozenError",
                          "undefined method `ord' for", "undefined method `bytesize'", "undefined method `force_encoding'",
                          "Encoding::CompatibilityError", "invalid byte sequence"]
        guard signatures.contains(where: { text.contains($0) }) else { return nil }
        let rgss = GameFolder.rgssVersion(in: game.folder) ?? 1
        switch game.rubyVersion {
        case MKXP_RUBY_31: return rgss >= 3 ? .ruby19 : .ruby18
        case MKXP_RUBY_19: return rgss >= 3 ? .ruby31 : .ruby18
        default: return .ruby19
        }
    }

    /// What the player can do about an error. A missing stock graphic
    /// or sound means the game counts on the RTP.
    private static func hint(for text: String) -> String {
        if let file = RTPStore.missingFile(in: text), RTPStore.isRTPAsset(file) {
            let rgss = EngineSession.shared.currentGame.flatMap { GameFolder.rgssVersion(in: $0.folder) }
            if let kind = rgss.flatMap(RTPStore.Kind.init(rgss:)), !RTPStore.isInstalled(kind) {
                return String(localized: "Falta o arquivo \(file), que vem no RTP do \(kind.name). Importe o RTP uma vez pela aba Importar, como pasta ou .zip, e abra o jogo de novo.")
            }
            return String(localized: "Falta o arquivo \(file). Confira se o jogo foi importado inteiro.")
        }
        return String(localized: "Se o jogo não abre, tente outra versão do Ruby: segure o jogo na biblioteca e toque em Ruby.")
    }

    private func presentEngineMessage(_ text: String, isError: Bool) {
        if isError {
            GameLog.shared.error(text)
        } else if !text.isEmpty {
            GameLog.shared.note("aviso do jogo: \(text)")
        }
        guard let screen = gameScreen, !text.isEmpty else {
            isError ? mkxp_signalErrorDismissed() : mkxp_signalInfoDismissed()
            return
        }
        let shown = text.count > 900 ? String(text.prefix(900)) + "…" : text
        let alert: UIAlertController
        if isError {
            let title = currentGame.map { String(localized: "\($0.title) encontrou um erro") } ?? String(localized: "O jogo encontrou um erro")
            let hint = "\n\n" + Self.hint(for: text)
            alert = UIAlertController(title: title, message: shown + hint, preferredStyle: .alert)
            // An error typical of the wrong Ruby: one tap picks the other
            // one for the next time the game opens.
            if let game = currentGame, let other = Self.rubySuggestion(for: text, game: game) {
                alert.message = shown + "\n\n" + String(localized: "Este erro costuma acontecer quando o jogo roda numa versão do Ruby diferente da que foi feito.")
                alert.addAction(UIAlertAction(title: String(localized: "Usar Ruby \(other.label) neste jogo"), style: .default) { _ in
                    RubyChoice.set(other, for: game.id)
                    GameLog.shared.note("Ruby trocado para \(other.label) depois de um erro")
                    mkxp_signalErrorDismissed()
                    EngineSession.shared.rubyChangedAfterError = other.label
                })
            }
            alert.addAction(UIAlertAction(title: String(localized: "Copiar erro"), style: .default) { _ in
                UIPasteboard.general.string = text
                mkxp_signalErrorDismissed()
            })
            alert.addAction(UIAlertAction(title: String(localized: "Fechar"), style: .cancel) { _ in
                mkxp_signalErrorDismissed()
            })
        } else {
            alert = UIAlertController(title: currentGame?.title, message: shown, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in
                mkxp_signalInfoDismissed()
            })
        }
        present(alert, over: screen, isError: isError, attempt: 0)
    }

    /// The engine waits until the alert is closed, so it must show: a
    /// sheet on its way out or another alert would make `present` fail
    /// in silence and leave the game stuck. Tries again a moment later;
    /// after ~6 s gives up and lets the game go on.
    private func present(_ alert: UIAlertController, over screen: UIViewController, isError: Bool, attempt: Int) {
        var top: UIViewController = screen
        while let presented = top.presentedViewController, !presented.isBeingDismissed { top = presented }
        let blocked = top.presentedViewController != nil || top is UIAlertController || top.isBeingPresented
        guard blocked else {
            top.present(alert, animated: true)
            return
        }
        guard attempt < 20 else {
            GameLog.shared.note("alerta do motor não pôde ser mostrado")
            isError ? mkxp_signalErrorDismissed() : mkxp_signalInfoDismissed()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.present(alert, over: screen, isError: isError, attempt: attempt + 1)
        }
    }

    // MARK: - Text input

    /// The engine fires this on its own thread when a game turns text
    /// input on or off (`Input.text_input`).
    nonisolated private func observeTextInput() {
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
        windowWatcher = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard let pointer = mkxp_getGameWindow(), let gameScreen = self.gameScreen else { return }
                let window = Unmanaged<UIWindow>.fromOpaque(pointer).takeUnretainedValue()
                guard gameScreen.adopt(gameWindow: window) else { return }
                self.windowWatcher?.invalidate()
                self.windowWatcher = nil
            }
        }
    }
}
