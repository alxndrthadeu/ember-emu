import AppKit

/// Phase 1 of Ember for Mac: proof that the engine runs on macOS.
/// Opens the demo game (A Última Brasa) in the engine's own window and
/// quits when it ends. The desk library comes in phase 2.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let demo = Bundle.main.url(forResource: "EmberDemo", withExtension: nil) else {
            fatalError("No demo game in the bundle (scripts/build-demo.rb)")
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let games = support.appendingPathComponent("Games", isDirectory: true)
        let game = games.appendingPathComponent("A Última Brasa", isDirectory: true)
        let userData = support.appendingPathComponent("UserData/A Última Brasa", isDirectory: true)
        let fm = FileManager.default
        // The engine writes next to the game (path cache, saves): run a
        // copy, never the bundle.
        try? fm.removeItem(at: game)
        try? fm.createDirectory(at: games, withIntermediateDirectories: true)
        try? fm.createDirectory(at: userData, withIntermediateDirectories: true)
        try? fm.copyItem(at: demo, to: game)

        let resources = Bundle.main.resourceURL!
        // The engine's assets, as a Mac bundle (scripts/embed-engine.sh).
        let assets = resources.appendingPathComponent("Assets.bundle/Contents/Resources")
        mkxp_setActiveRubyVersion(MKXP_RUBY_19)
        mkxp_setLauncherIdentity("Ember", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        mkxp_setUserDataDirectory(userData.path)
        mkxp_setSharedFontsDirectory(assets.appendingPathComponent("Fonts").path)
        mkxp_setCABundlePath(assets.appendingPathComponent("cacert.pem").path)
        mkxp_setManagedConfigDir(game.path)
        mkxp_setGamePath(game.path)

        // Not a main-queue block: mkxp_run_app holds the main thread for
        // the whole session (see app_bridge.h).
        RunLoop.main.perform {
            _ = mkxp_run_app(CommandLine.argc, CommandLine.unsafeArgv)
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
