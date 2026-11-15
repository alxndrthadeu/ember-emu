import Foundation

/// Finds the PC keys a game reads beyond the RGSS buttons (F5 for a
/// minimap, numbers for skills, Ctrl to skip text), so the game's
/// controls screen can offer them first. Reads the same script text as
/// `ScriptScanner`:
///
/// - `Input::F5`…`Input::F9`, `Input::CTRL`, `Input::ALT` (RGSS buttons
///   bound to one key each);
/// - `Input.triggerex?(:F5)`, `pressex?`, `repeatex?`, `releaseex?` with
///   an SDL scancode name (mkxp-z, Essentials v19+) or a Windows
///   virtual-key number (older Essentials);
/// - `GetAsyncKeyState` / `GetKeyState` called with a virtual-key number.
///
/// Arrows are left out (the D-pad has them), and so are F1, F2 and F12,
/// which the engine keeps for itself. Lines that only run in the
/// editor's test play (`$DEBUG`: Ctrl walks through walls, F9 opens the
/// debug menu), comments and `when` lines (key tables in input
/// modules) do not count.
enum GameKeyScanner {
    /// Keys most used first; at most `limit`.
    static func keys(inCode code: String, limit: Int = 16) -> [KeyboardKey] {
        var counts: [Int32: Int] = [:]
        func add(_ scancode: Int32?) {
            guard let scancode, !reserved.contains(scancode) else { return }
            counts[scancode, default: 0] += 1
        }
        for match in code.captures(of: #"Input::(F[5-9]|CTRL|ALT)\b"#) {
            add(symbolScancode(match))
        }
        for match in code.captures(of: #"(?:trigger|press|repeat|release)ex\?\s*\(?\s*(:[A-Za-z_0-9]+|0x[0-9A-Fa-f]+|\d+)"#) {
            add(match.hasPrefix(":") ? symbolScancode(String(match.dropFirst())) : virtualKeyScancode(match))
        }
        for match in code.captures(of: #"Get(?:Async)?KeyState\w*\.call\(\s*(0x[0-9A-Fa-f]+|\d+)\s*\)"#) {
            add(virtualKeyScancode(match))
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { KeyboardKey(scancode: $0.key) }
    }

    /// F1, F2, F12 (engine) and the arrows (D-pad).
    private static let reserved: Set<Int32> = [58, 59, 69, 79, 80, 81, 82]

    /// An SDL scancode name as mkxp-z spells it (`:A`, `:NUMBER_1`, `:F5`,
    /// `:RETURN`, `:LCTRL`), or an RGSS one-key button (`CTRL`, `ALT`).
    static func symbolScancode(_ name: String) -> Int32? {
        let name = name.uppercased()
        if name.count == 1, let scalar = name.unicodeScalars.first, ("A"..."Z").contains(name) {
            return Int32(scalar.value) - 65 + 4
        }
        if name.hasPrefix("NUMBER_"), let digit = Int32(name.dropFirst(7)), (0...9).contains(digit) {
            return digit == 0 ? 39 : 29 + digit
        }
        if name.hasPrefix("F"), let number = Int32(name.dropFirst()), (1...12).contains(number) {
            return 57 + number
        }
        return [
            "RETURN": 40, "ENTER": 40, "ESCAPE": 41, "BACKSPACE": 42, "TAB": 43, "SPACE": 44,
            "CTRL": 224, "LCTRL": 224, "RCTRL": 224, "SHIFT": 225, "LSHIFT": 225, "RSHIFT": 225,
            "ALT": 226, "LALT": 226, "RALT": 226,
            "HOME": 74, "PAGEUP": 75, "END": 77, "PAGEDOWN": 78,
            "UP": 82, "DOWN": 81, "LEFT": 80, "RIGHT": 79,
        ][name]
    }

    /// A Windows virtual-key code ("0x74", "116").
    static func virtualKeyScancode(_ text: String) -> Int32? {
        let value = text.lowercased().hasPrefix("0x") ? Int(text.dropFirst(2), radix: 16) : Int(text)
        guard let vk = value else { return nil }
        switch vk {
        case 0x41...0x5A: return Int32(vk - 0x41 + 4)
        case 0x31...0x39: return Int32(vk - 0x31 + 30)
        case 0x30: return 39
        case 0x70...0x7B: return Int32(vk - 0x70 + 58)
        case 0x0D: return 40
        case 0x1B: return 41
        case 0x08: return 42
        case 0x09: return 43
        case 0x20: return 44
        case 0x10, 0xA0, 0xA1: return 225
        case 0x11, 0xA2, 0xA3: return 224
        case 0x12, 0xA4, 0xA5: return 226
        case 0x21: return 75
        case 0x22: return 78
        case 0x23: return 77
        case 0x24: return 74
        case 0x25: return 80
        case 0x26: return 82
        case 0x27: return 79
        case 0x28: return 81
        default: return nil
        }
    }
}

/// The keys found in each game's scripts (`ControllerTypeStore.detect`
/// reads them with the controller type).
enum GameKeyStore {
    /// Bumped when the scanner changes: games are read again.
    private static let version = 1
    private static func key(_ id: String) -> String { "controls.keys.v\(version).\(id)" }

    /// Nil until the scripts are read.
    static func keys(for id: String) -> [KeyboardKey]? {
        (UserDefaults.standard.array(forKey: key(id)) as? [Int])?.map { KeyboardKey(scancode: Int32($0)) }
    }

    static func set(_ keys: [KeyboardKey], for id: String) {
        UserDefaults.standard.set(keys.map { Int($0.scancode) }, forKey: key(id))
    }

    static func forget(_ id: String) {
        UserDefaults.standard.removeObject(forKey: key(id))
    }
}

private extension String {
    /// The first capture group of every match outside test-play lines.
    func captures(of pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let text = self as NSString
        return regex.matches(in: self, range: NSRange(location: 0, length: text.length)).compactMap { match in
            let line = text.substring(with: text.lineRange(for: match.range))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !line.contains("$DEBUG"), !line.contains("$TEST"),
                  !trimmed.hasPrefix("#"), !trimmed.hasPrefix("when ") else { return nil }
            return text.substring(with: match.range(at: 1))
        }
    }
}
