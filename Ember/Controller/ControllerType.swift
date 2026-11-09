import Foundation

/// The kind of controller a game gets on screen. RPG Maker games follow
/// different control schemes: most need a D-pad and two buttons, some
/// use X/Y/Z, action games want a stick and more buttons.
enum ControllerType: String, CaseIterable, Identifiable, Codable {
    case classic2, classic4, modern

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic2: String(localized: "Clássico 2 botões")
        case .classic4: String(localized: "Clássico 4 botões")
        case .modern: String(localized: "Moderno")
        }
    }

    var detail: String {
        switch self {
        case .classic2: String(localized: "D-pad, A, B, L, R, Start e Select. Serve para a maioria dos jogos.")
        case .classic4: String(localized: "Igual ao de 2 botões, mais X e Y, para jogos que usam mais teclas.")
        case .modern: String(localized: "Analógico, A, B, X, Y e quatro gatilhos, para jogos de ação.")
        }
    }

    var icon: String {
        switch self {
        case .classic2: "gamecontroller"
        case .classic4: "circle.grid.cross"
        case .modern: "l.joystick.fill"
        }
    }

    /// Buttons this controller draws besides the D-pad (or stick).
    var buttons: Set<ControlButton> {
        switch self {
        case .classic2: [.a, .b, .l, .r, .start, .select]
        case .classic4: [.a, .b, .x, .y, .l, .r, .start, .select]
        case .modern: Set(ControlButton.allCases)
        }
    }
}

/// Which controller each game uses: the player's choice, or what the
/// game's scripts suggest.
@MainActor
enum ControllerTypeStore {
    private static func chosenKey(_ id: String) -> String { "controls.type.\(id)" }
    private static func detectedKey(_ id: String) -> String { "controls.detected.\(id)" }
    private static func askedKey(_ id: String) -> String { "controls.asked.\(id)" }

    static func chosen(for id: String) -> ControllerType? {
        UserDefaults.standard.string(forKey: chosenKey(id)).flatMap(ControllerType.init(rawValue:))
    }

    static func set(_ type: ControllerType?, for id: String) {
        UserDefaults.standard.set(type?.rawValue, forKey: chosenKey(id))
        UserDefaults.standard.set(true, forKey: askedKey(id))
    }

    /// What the scripts suggest, once read (`detect`). Until then, and
    /// for games whose scripts cannot be read, Clássico 2 botões.
    static func detected(for id: String) -> ControllerType? {
        UserDefaults.standard.string(forKey: detectedKey(id)).flatMap(ControllerType.init(rawValue:))
    }

    static func type(for game: GameEntry) -> ControllerType {
        #if DEBUG
        // Development aid: EMBER_CONTROLLER=classic2|classic4|modern.
        if let forced = ProcessInfo.processInfo.environment["EMBER_CONTROLLER"].flatMap(ControllerType.init(rawValue:)) {
            return forced
        }
        #endif
        return chosen(for: game.id) ?? detected(for: game.id) ?? .classic2
    }

    /// Reads the scripts of games not read yet, off the main thread
    /// (a big game takes a second or two).
    static func detect(_ games: [GameEntry]) async {
        let pending = games.filter { detected(for: $0.id) == nil }.map { ($0.id, $0.folder) }
        guard !pending.isEmpty else { return }
        let found = await Task.detached(priority: .utility) {
            pending.map { ($0.0, ScriptScanner.suggestion(for: $0.1)) }
        }.value
        for (id, type) in found {
            UserDefaults.standard.set(type.rawValue, forKey: detectedKey(id))
        }
    }

    /// The player has not picked a controller for this game yet.
    static func needsChoice(_ game: GameEntry) -> Bool {
        !UserDefaults.standard.bool(forKey: askedKey(game.id))
    }

    static func markAsked(_ id: String) {
        UserDefaults.standard.set(true, forKey: askedKey(id))
    }

    static func forget(_ id: String) {
        for key in [chosenKey(id), detectedKey(id), askedKey(id)] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
