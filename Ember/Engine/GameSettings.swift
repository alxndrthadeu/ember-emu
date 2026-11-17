import Foundation

/// Settings that outlive a game session.
enum GameSettings {
    static let speedSteps = [1, 2, 3, 5]

    static var speed: Int {
        get { max(1, UserDefaults.standard.integer(forKey: "game.speed")) }
        set { UserDefaults.standard.set(newValue, forKey: "game.speed") }
    }

    /// Pushes the saved settings into the engine.
    static func apply() {
        mkxp_setFastForwardMultiplier(Int32(speed))
    }
}
