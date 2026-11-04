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

    private init() {}

    func launch(_ game: GameEntry) {
        guard state == .idle else { return }
        state = .preparing(game.title)
        // Games live in Documents/Games, which is writable: the engine
        // runs them in place (it writes a path cache next to them).
        start(game, in: game.folder)
    }

    // MARK: - Engine

    private func start(_ game: GameEntry, in folder: URL) {
        let resources = Bundle.main.resourceURL!
        let userData = GameStorage.userDataFolder(for: game)

        if let ruby = game.rubyVersion {
            mkxp_setActiveRubyVersion(ruby)
        }
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

        currentGame = game
        GameLayout.shared.observeEngine()
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
        windowWatcher?.invalidate()
        windowWatcher = nil
        gameScreen = nil
        if let libraryRoot {
            launcherWindow?.rootViewController = libraryRoot
        }
        libraryRoot = nil
        currentGame = nil
        state = .finished
        launcherWindow?.makeKeyAndVisible()
    }

    /// Ends the game. The engine stops at its next frame (also when
    /// paused), mkxp_run_app returns, and engineDidEnd brings the
    /// library back.
    func quit() {
        guard state == .running else { return }
        mkxp_requestTerminate()
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
