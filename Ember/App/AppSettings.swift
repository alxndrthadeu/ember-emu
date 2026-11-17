import Foundation

/// Settings from the Ajustes tab.
enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    /// Light taps on button presses.
    static var haptics: Bool {
        get { defaults.object(forKey: "settings.haptics") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "settings.haptics") }
    }

    /// How opaque the controller is in landscape, over the game, for
    /// skins that allow it.
    static var landscapeOpacity: Double {
        get { defaults.object(forKey: "settings.landscapeOpacity") as? Double ?? 0.8 }
        set { defaults.set(newValue, forKey: "settings.landscapeOpacity") }
    }

    /// Hide the on-screen buttons in landscape while a controller is
    /// connected.
    static var hideControlsWithController: Bool {
        get { defaults.object(forKey: "settings.hideWithController") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "settings.hideWithController") }
    }

    /// The speed a skin's fast-forward button uses.
    static var fastForwardSpeed: Int {
        get { defaults.object(forKey: "settings.fastForwardSpeed") as? Int ?? 3 }
        set { defaults.set(newValue, forKey: "settings.fastForwardSpeed") }
    }

    /// Send an imported .zip/.rar/.7z to the trash, to free its space.
    static var deleteArchiveAfterImport: Bool {
        get { defaults.object(forKey: "settings.deleteArchive") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "settings.deleteArchive") }
    }

    /// The FPS / CPU / memory readout during games.
    static var showPerformance: Bool {
        get { defaults.object(forKey: "settings.showPerformance") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "settings.showPerformance") }
    }

    /// Pause when the app leaves the screen.
    static var pauseOnBackground: Bool {
        get { defaults.object(forKey: "settings.pauseOnBackground") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "settings.pauseOnBackground") }
    }
}
