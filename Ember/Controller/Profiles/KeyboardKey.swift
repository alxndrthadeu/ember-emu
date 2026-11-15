import Foundation

/// A PC keyboard key a button can press ("Tecla do teclado" in a control
/// profile), for games that read keys beyond the RGSS buttons: numbers
/// for skills, letters for shortcuts. Values are SDL scancodes.
/// F1, F2 and F12 are left out: the engine uses them (settings, FPS,
/// reset).
struct KeyboardKey: Codable, Hashable, Identifiable {
    let scancode: Int32

    var id: Int32 { scancode }

    var name: String {
        switch scancode {
        case 4...29: String(UnicodeScalar(UInt8(65 + scancode - 4)))
        case 30...38: "\(scancode - 29)"
        case 39: "0"
        case 40: "Enter"
        case 41: "Esc"
        case 42: "Backspace"
        case 43: "Tab"
        case 44: String(localized: "Espaço")
        case 60...68: "F\(scancode - 57)"
        case 74: "Home"
        case 75: "Page Up"
        case 77: "End"
        case 78: "Page Down"
        case 224: "Ctrl"
        case 225: "Shift"
        case 226: "Alt"
        default: "#\(scancode)"
        }
    }

    static let all: [KeyboardKey] = {
        var codes: [Int32] = Array(4...29) + Array(30...39)
        codes += [44, 40, 41, 42, 43, 225, 224, 226, 75, 78, 74, 77]
        codes += Array(60...68)  // F3–F11
        return codes.map(KeyboardKey.init(scancode:))
    }()

    static let space = KeyboardKey(scancode: 44)
}
