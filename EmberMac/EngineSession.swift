import AppKit

/// Runs one game in this instance of Ember for Mac. The library starts
/// a new instance per game (`MacLibrary.play`), with `--play <id>`, so
/// a game always gets a fresh engine and Ruby VM, and closing its window
/// ends only that game. Same interface as the iPhone app's
/// EngineSession, which the shared code (profiles, cheats, filters)
/// calls.
@MainActor
@Observable
final class EngineSession {
    static let shared = EngineSession()

    enum State: Equatable {
        case idle
        case running
        case finished
    }

    private(set) var state: State = .idle
    private(set) var currentGame: GameEntry?
    /// Sound off for this session only, without touching the setting
    /// (development tests).
    var mutedForTest = false
    #if DEBUG
    /// A test script from the ember-play link (DevelopmentScript).
    var scriptForLaunch: String?
    private var pendingScript: String?
    #endif
    private var sessionID: UUID?
    private var historyTimer: Timer?
    private var windowWatcher: Timer?
    private var coverTimer: Timer?
    /// Keeps macOS from slowing the game (and the iPhone's link) down when
    /// its window is not in front (App Nap).
    private var activity: NSObjectProtocol?
    private var screenshotRequest: ((NSImage) -> Void)?

    private init() {}

    func launch(_ game: GameEntry, resumeSlot: String? = nil) {
        guard state == .idle else { return }
        currentGame = game
        let resources = Bundle.main.resourceURL!
        // The engine's assets, as a Mac bundle (scripts/embed-engine.sh).
        let assets = resources.appendingPathComponent("Assets.bundle/Contents/Resources")
        let userData = GameStorage.userDataFolder(for: game)

        StateStore.prepareEnvironment(gameID: game.id, resumeSlot: resumeSlot)
        mkxp_setActiveRubyVersion(game.rubyVersion)
        EngineConfig.apply(for: game)
        GameLog.shared.begin(game: game, details: [
            "Ruby: \(RubyChoice.label(for: game.rubyVersion))",
            "Retomar: \(resumeSlot ?? "não")",
        ])
        mkxp_setUseInGameKeyboard(InGameKeyboard.isOn(for: game.id))
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        mkxp_setLauncherIdentity("Ember", version)
        SaveSync.deviceName = Host.current().localizedName ?? "Mac"
        mkxp_setUserDataDirectory(userData.path)
        mkxp_setSharedFontsDirectory(assets.appendingPathComponent("Fonts").path)
        mkxp_setCABundlePath(assets.appendingPathComponent("cacert.pem").path)
        mkxp_setManagedConfigDir(game.folder.path)
        mkxp_setGamePath(game.folder.path)
        GameSettings.apply()
        #if DEBUG
        pendingScript = scriptForLaunch
        #endif

        sessionID = PlayHistory.begin(gameID: game.id, title: game.title)
        historyTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { EngineSession.shared.touchSession() }
        }
        Self.observeMessages()
        state = .running
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical, .idleDisplaySleepDisabled],
            reason: "Jogo rodando")
        watchForGameWindow()
        // An iPhone can be this game's controller.
        RemoteControllerServer.shared.onChange = { EngineSession.shared.showController() }
        RemoteControllerServer.shared.start(for: game)
        // A cover for the shelf every minute (the last frame when the
        // window closes by its red button).
        // The player's "game sound" once OpenAL exists.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
            MainActor.assumeIsolated {
                let session = EngineSession.shared
                if !session.soundOn || session.mutedForTest { alListenerf(0x100A, 0) }
            }
        }
        coverTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { EngineSession.shared.saveCover() }
        }
        #if DEBUG
        DevelopmentScript.run(ProcessInfo.processInfo.environment["EMBER_SCRIPT"] ?? pendingScript)
        #endif

        // Not a main-queue block: mkxp_run_app holds the main thread for
        // the whole session (see app_bridge.h).
        RunLoop.main.perform {
            _ = mkxp_run_app(CommandLine.argc, CommandLine.unsafeArgv)
            MainActor.assumeIsolated { EngineSession.shared.engineDidEnd() }
        }
    }

    private func touchSession() {
        if let sessionID { Task.detached(priority: .utility) { PlayHistory.touch(sessionID) } }
    }

    private func engineDidEnd() {
        RemoteControllerServer.shared.stop()
        historyTimer?.invalidate()
        coverTimer?.invalidate()
        if let sessionID { PlayHistory.touch(sessionID) }
        GameLog.shared.end()
        state = .finished
        // The saves go to iCloud before this instance quits (up to 15 s),
        // so the iPhone finds them right away.
        guard let game = currentGame, SaveSync.isEnabled else { return NSApp.terminate(nil) }
        let folders = SaveSync.GameFolders(game)
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { _ = await Task.detached { SaveSync.sync([folders]) }.value }
                group.addTask { try? await Task.sleep(for: .seconds(15)) }
                await group.next()
                group.cancelAll()
            }
            NSApp.terminate(nil)
        }
    }

    /// The Mac has a keyboard: nothing to open.
    func openKeyboard() {}

    /// Keeps the last frame as the cover, then ends the game.
    func quit() {
        saveCover()
        Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
            mkxp_requestTerminate()
        }
    }

    /// "iPhone de Ana · controle" under the window title.
    func showController() {
        guard let pointer = mkxp_getGameWindow() else { return }
        let window = Unmanaged<NSWindow>.fromOpaque(pointer).takeUnretainedValue()
        let title = currentGame?.title ?? "Ember"
        if let name = RemoteControllerServer.shared.connectedName {
            window.title = "\(title) — " + String(localized: "controle: \(name)")
        } else {
            window.title = title
        }
    }

    // MARK: - Frames (cover, screenshot)

    /// The frame on screen now, without pausing: the engine copies the
    /// next frames into a buffer (the same one Play on TV uses) while
    /// asked, so turn it on, take one, turn it off.
    func grabFrame(_ done: @escaping @MainActor (NSImage) -> Void) {
        mkxp_setFrameStreamEnabled(true)
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
            MainActor.assumeIsolated {
                defer { mkxp_setFrameStreamEnabled(false) }
                var width: Int32 = 0, height: Int32 = 0, sequence: UInt32 = 0
                var pixels = [UInt8](repeating: 0, count: 1920 * 1080 * 4)
                let copied = pixels.withUnsafeMutableBytes { raw in
                    mkxp_copyStreamFrame(raw.bindMemory(to: UInt8.self).baseAddress, Int32(raw.count),
                                         &width, &height, &sequence)
                }
                guard copied, width > 0, height > 0,
                      let provider = CGDataProvider(data: Data(pixels.prefix(Int(width * height * 4))) as CFData),
                      let image = CGImage(width: Int(width), height: Int(height), bitsPerComponent: 8, bitsPerPixel: 32,
                                          bytesPerRow: Int(width) * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
                else { return }
                done(NSImage(cgImage: image, size: NSSize(width: Int(width), height: Int(height))))
            }
        }
    }

    func saveCover() {
        guard let game = currentGame else { return }
        grabFrame { GameCovers.saveSnapshot($0, forGameID: game.id) }
    }

    /// Saves the frame as a PNG in Pictures/Ember.
    func saveScreenshot(_ done: @escaping @MainActor (URL?) -> Void) {
        guard let game = currentGame else { return done(nil) }
        grabFrame { image in
            let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Ember", isDirectory: true)
            try? FileManager.default.createDirectory(at: pictures, withIntermediateDirectories: true)
            let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                .replacingOccurrences(of: ":", with: ".")
            let url = pictures.appendingPathComponent("\(game.title) \(stamp).png")
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]),
                  (try? png.write(to: url)) != nil
            else { return done(nil) }
            done(url)
        }
    }

    /// Game sound on or off, now and next time (the iPhone's setting).
    var soundOn: Bool {
        get { UserDefaults.standard.object(forKey: "settings.gameSound") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "settings.gameSound")
            alListenerf(0x100A, newValue ? 1 : 0)
        }
    }

    func requestState(_ verb: String, slot: String) async -> StateStore.Outcome {
        guard let game = currentGame else { return .noAnswer }
        let outcome = await StateStore.request(verb, slot: slot, gameID: game.id)
        GameLog.shared.note("estado \(verb == "save" ? "salvo" : "carregado") (\(slot)): \(outcome)")
        return outcome
    }

    // MARK: - The game window

    /// SDL makes its window once the engine is up: give it the game's
    /// title, a sensible size and keep it in proportion.
    private func watchForGameWindow() {
        windowWatcher = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated {
                let session = EngineSession.shared
                guard let pointer = mkxp_getGameWindow() else { return }
                let window = Unmanaged<NSWindow>.fromOpaque(pointer).takeUnretainedValue()
                session.windowWatcher?.invalidate()
                session.windowWatcher = nil
                window.title = session.currentGame?.title ?? "Ember"
                // The engine sizes its window to the game's resolution a
                // moment after making it: grow it after that.
                Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
                    MainActor.assumeIsolated { EngineSession.shared.dress(window) }
                }
            }
        }
    }

    private func dress(_ window: NSWindow) {
        window.title = currentGame?.title ?? "Ember"
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.collectionBehavior.insert(.fullScreenPrimary)
        // As big as fits comfortably (most of the screen), in the game's
        // proportion, up to 3 times its size; the engine scales the
        // picture (Pixel filter keeps it sharp).
        let content = window.contentRect(forFrameRect: window.frame).size
        if let screen = window.screen?.visibleFrame, content.width > 0, content.height > 0 {
            let title = window.frame.height - content.height
            let scale = min(3, (screen.width * 0.85) / content.width, (screen.height * 0.9 - title) / content.height)
            if scale > 1 {
                window.setContentSize(NSSize(width: (content.width * scale).rounded(),
                                             height: (content.height * scale).rounded()))
                window.center()
            }
            window.contentAspectRatio = content
            window.contentMinSize = content
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - Engine messages

    /// The engine blocks until an error or a game's message box is
    /// closed. Nonisolated: the engine calls these on its own thread.
    nonisolated private static func observeMessages() {
        mkxp_setErrorMessageCallback({ message, _ in
            let text = message.map { String(cString: $0) } ?? ""
            onMainRunLoop { EngineSession.shared.present(text, isError: true) }
        }, nil)
        mkxp_setInfoMessageCallback({ message, _ in
            let text = message.map { String(cString: $0) } ?? ""
            onMainRunLoop { EngineSession.shared.present(text, isError: false) }
        }, nil)
    }

    private func present(_ text: String, isError: Bool) {
        if isError { GameLog.shared.error(text) } else { GameLog.shared.note("aviso do jogo: \(text)") }
        let alert = NSAlert()
        alert.alertStyle = isError ? .warning : .informational
        alert.messageText = isError
            ? String(localized: "\(currentGame?.title ?? "O jogo") encontrou um erro")
            : (currentGame?.title ?? "Ember")
        alert.informativeText = text.count > 900 ? String(text.prefix(900)) + "…" : text
        alert.addButton(withTitle: "OK")
        if isError { alert.addButton(withTitle: String(localized: "Copiar erro")) }
        let answer = alert.runModal()
        if answer == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        isError ? mkxp_signalErrorDismissed() : mkxp_signalInfoDismissed()
    }
}

/// Runs `body` on the main thread through its run loop. While a game
/// runs, the engine holds the main thread and pumps its run loop itself,
/// so blocks on the main dispatch queue would wait for the game to end.
nonisolated func onMainRunLoop(_ body: @escaping @MainActor () -> Void) {
    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
        MainActor.assumeIsolated { body() }
    }
    CFRunLoopWakeUp(CFRunLoopGetMain())
}
