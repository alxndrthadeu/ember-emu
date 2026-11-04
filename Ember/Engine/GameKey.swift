import UIKit

/// The buttons Ember draws, mapped to the keys the engine's default
/// bindings read (src/input/keybindings.cpp in the engine).
///
/// Essentials changed its controls in v19, so Start and Select do not
/// mean the same thing in every game. The mapping below follows v19+;
/// per-game remapping comes with the controls settings.
enum GameKey: Hashable {
    case up, down, left, right
    /// Input::C (USE): confirm, talk, interact.
    case confirm
    /// Input::B (BACK): back, cancel. Held, it runs in Essentials v19+.
    case back
    /// Input::A (ACTION): opens the menu in Essentials v19+.
    case start
    /// Input::Z (SPECIAL): the Ready menu in Essentials v19+.
    case select
    /// Input::L and Input::R (AUX1 / AUX2 in Essentials v19+).
    case l, r
    /// Text entry only.
    case enter, backspace

    var scancode: Int32 {
        switch self {
        case .up: Int32(MKXP_SCANCODE_UP)
        case .down: Int32(MKXP_SCANCODE_DOWN)
        case .left: Int32(MKXP_SCANCODE_LEFT)
        case .right: Int32(MKXP_SCANCODE_RIGHT)
        case .confirm, .enter: Int32(MKXP_SCANCODE_RETURN)
        case .back: Int32(MKXP_SCANCODE_ESCAPE)
        case .start: Int32(MKXP_SCANCODE_LSHIFT)
        case .select: Int32(MKXP_SCANCODE_D)
        case .l: Int32(MKXP_SCANCODE_Q)
        case .r: Int32(MKXP_SCANCODE_W)
        case .backspace: Int32(MKXP_SCANCODE_BACKSPACE)
        }
    }

    func press() { mkxp_injectKeyEvent(scancode, 1) }
    func release() { mkxp_injectKeyEvent(scancode, 0) }
}

/// Taps keys one at a time, each held long enough for the game to see.
///
/// Games read input once per frame, and RPG Maker XP games run at
/// 40 fps: a press and release in the same instant falls between two
/// frames and is lost. That is why Enter did nothing on the keyboard.
@MainActor
enum KeyTapper {
    private static var queue: [GameKey] = []
    private static var running = false

    static func tap(_ key: GameKey) {
        queue.append(key)
        guard !running else { return }
        running = true
        Task { @MainActor in
            while !queue.isEmpty {
                let key = queue.removeFirst()
                key.press()
                try? await Task.sleep(for: .milliseconds(70))
                key.release()
                try? await Task.sleep(for: .milliseconds(40))
            }
            running = false
        }
    }
}

/// Light haptic feedback on button presses.
@MainActor
enum Haptics {
    private static let generator = UIImpactFeedbackGenerator(style: .light)

    static func tap() { generator.impactOccurred() }
}
