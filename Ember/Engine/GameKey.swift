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
    /// The 4-button and modern controllers' extra buttons. They always
    /// go through the control profile (ControlButton); the keys here
    /// are only a fallback.
    case x, y, l2, r2
    /// Text entry only.
    case enter, backspace
    /// Input::HOME: opens the engine's cheat menu (when cheats are on).
    case home

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
        case .x: Int32(MKXP_SCANCODE_A)
        case .y: Int32(MKXP_SCANCODE_S)
        case .l2: Int32(MKXP_SCANCODE_F9)
        case .r2: Int32(MKXP_SCANCODE_F10)
        case .backspace: Int32(MKXP_SCANCODE_BACKSPACE)
        case .home: Int32(MKXP_SCANCODE_HOME)
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
    private struct Tap {
        let scancode: Int32
        let shifted: Bool
    }

    private static var queue: [Tap] = []
    private static var running = false

    static func tap(_ key: GameKey) {
        enqueue(Tap(scancode: key.scancode, shifted: false))
    }

    /// Types one character as the key that makes it on a US keyboard,
    /// for games that read the keyboard key by key (old Essentials name
    /// entry). Characters with no key are skipped.
    static func type(_ character: Character) {
        guard let (scancode, shifted) = scancode(for: character) else { return }
        enqueue(Tap(scancode: scancode, shifted: shifted))
    }

    private static func enqueue(_ tap: Tap) {
        queue.append(tap)
        guard !running else { return }
        running = true
        Task { @MainActor in
            let shift = Int32(MKXP_SCANCODE_LSHIFT)
            while !queue.isEmpty {
                let tap = queue.removeFirst()
                if tap.shifted { mkxp_injectKeyEvent(shift, 1) }
                mkxp_injectKeyEvent(tap.scancode, 1)
                try? await Task.sleep(for: .milliseconds(70))
                mkxp_injectKeyEvent(tap.scancode, 0)
                if tap.shifted { mkxp_injectKeyEvent(shift, 0) }
                try? await Task.sleep(for: .milliseconds(40))
            }
            running = false
        }
    }

    private static func scancode(for character: Character) -> (Int32, Bool)? {
        // Accents fold to their base letter (é → e): RGSS keyboards
        // only know the US layout.
        let folded = String(character).folding(options: .diacriticInsensitive, locale: nil)
        guard let c = folded.unicodeScalars.first, folded.unicodeScalars.count == 1 else { return nil }
        let a = Int32(MKXP_SCANCODE_A)
        switch c {
        case "a"..."z": return (a + Int32(c.value - 97), false)
        case "A"..."Z": return (a + Int32(c.value - 65), true)
        case "1"..."9": return (Int32(MKXP_SCANCODE_1) + Int32(c.value - 49), false)
        case "0": return (Int32(MKXP_SCANCODE_0), false)
        case " ": return (Int32(MKXP_SCANCODE_SPACE), false)
        case "-": return (Int32(MKXP_SCANCODE_MINUS), false)
        case "_": return (Int32(MKXP_SCANCODE_MINUS), true)
        case ".": return (Int32(MKXP_SCANCODE_PERIOD), false)
        case ",": return (Int32(MKXP_SCANCODE_COMMA), false)
        case "!": return (Int32(MKXP_SCANCODE_1), true)
        case "?": return (Int32(MKXP_SCANCODE_SLASH), true)
        case "'": return (Int32(MKXP_SCANCODE_APOSTROPHE), false)
        default: return nil
        }
    }
}

/// Light haptic feedback on button presses.
@MainActor
enum Haptics {
    private static let generator = UIImpactFeedbackGenerator(style: .light)

    static func tap() {
        guard AppSettings.haptics else { return }
        generator.impactOccurred()
    }
}
