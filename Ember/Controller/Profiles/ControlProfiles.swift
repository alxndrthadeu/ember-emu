import Foundation
import GameController

/// A button the player presses: on the screen (skins) or on a
/// controller. The D-pad and stick always walk, so they are not here.
enum ControlButton: String, Codable, CaseIterable, Identifiable {
    case a, b, x, y, l, r, l2, r2, start, select

    var id: String { rawValue }

    var label: String {
        switch self {
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .l: "L"
        case .r: "R"
        case .l2: "L2 / LT"
        case .r2: "R2 / RT"
        case .start: String(localized: "Start")
        case .select: String(localized: "Select")
        }
    }

    /// The skin button behind a GameKey (skins speak GameKey).
    init?(skinKey key: GameKey) {
        switch key {
        case .confirm: self = .a
        case .back: self = .b
        case .l: self = .l
        case .r: self = .r
        case .start: self = .start
        case .select: self = .select
        case .x: self = .x
        case .y: self = .y
        case .l2: self = .l2
        case .r2: self = .r2
        default: return nil
        }
    }
}

/// What a button does. Game actions are RGSS buttons, sent as the keys
/// the engine's default bindings read (GameKey has the full table).
enum GameAction: String, Codable, CaseIterable, Identifiable {
    case confirm, back, action, special, x, y, l, r
    case emberMenu, fastForward, keyboard, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .confirm: String(localized: "Confirmar")
        case .back: String(localized: "Voltar")
        case .action: String(localized: "Menu / Correr")
        case .special: String(localized: "Especial")
        case .x: String(localized: "Botão X do jogo")
        case .y: String(localized: "Botão Y do jogo")
        case .l: String(localized: "L do jogo")
        case .r: String(localized: "R do jogo")
        case .emberMenu: String(localized: "Menu do Ember")
        case .fastForward: String(localized: "Avanço rápido (segurar)")
        case .keyboard: String(localized: "Teclado")
        case .none: String(localized: "Nada")
        }
    }

    /// What the action means in a Pokémon Essentials game, the most
    /// common kind.
    var detail: String {
        switch self {
        case .confirm: String(localized: "Falar, interagir, escolher (Enter, Input::C)")
        case .back: String(localized: "Cancelar. Em jogos antigos abre o menu; nos novos, segurar corre (Esc, Input::B)")
        case .action: String(localized: "Nos jogos novos abre o menu; nos antigos, segurar corre (Shift, Input::A)")
        case .special: String(localized: "Menu rápido de itens registrados (D, Input::Z)")
        case .x: String(localized: "Tecla A do PC (Input::X)")
        case .y: String(localized: "Tecla S do PC (Input::Y)")
        case .l: String(localized: "Tecla Q do PC (Input::L)")
        case .r: String(localized: "Tecla W do PC (Input::R)")
        case .emberMenu: String(localized: "Pausa: velocidade, captura, sair")
        case .fastForward: String(localized: "Acelera enquanto estiver apertado")
        case .keyboard: String(localized: "Abre o teclado do iPhone")
        case .none: String(localized: "O botão não faz nada")
        }
    }

    var scancode: Int32? {
        switch self {
        case .confirm: GameKey.confirm.scancode
        case .back: GameKey.back.scancode
        case .action: GameKey.start.scancode
        case .special: GameKey.select.scancode
        case .x: Int32(MKXP_SCANCODE_A)
        case .y: Int32(MKXP_SCANCODE_S)
        case .l: GameKey.l.scancode
        case .r: GameKey.r.scancode
        default: nil
        }
    }
}

/// A named set of button → action choices.
struct ControlProfile: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var mapping: [ControlButton: GameAction]

    var isBuiltIn: Bool { id.hasPrefix("builtin.") }

    func action(for button: ControlButton) -> GameAction {
        mapping[button] ?? .none
    }

    /// Pokémon Essentials v19 and newer, and most games on Ruby 3.
    static let standard = ControlProfile(
        id: "builtin.padrao", name: String(localized: "Padrão"),
        mapping: [.a: .confirm, .b: .back, .x: .action, .y: .x, .l: .l, .r: .r,
                  .l2: .special, .r2: .fastForward, .start: .action, .select: .special])

    /// Older Essentials and plain RPG Maker XP/VX: the menu opens on
    /// Input::B and holding Input::A runs, so Start opens the menu and
    /// Select runs.
    static let classic = ControlProfile(
        id: "builtin.classico", name: String(localized: "Clássico"),
        mapping: [.a: .confirm, .b: .back, .x: .action, .y: .x, .l: .l, .r: .r,
                  .l2: .special, .r2: .fastForward, .start: .back, .select: .action])

    /// Games that use Input::X and Input::Y (Clássico 4 botões and
    /// Moderno controllers): Clássico, with X and Y sending the game's
    /// own X and Y (the A and S keys on a PC).
    static let fourButtons = ControlProfile(
        id: "builtin.quatro", name: String(localized: "4 botões"),
        mapping: [.a: .confirm, .b: .back, .x: .x, .y: .y, .l: .l, .r: .r,
                  .l2: .special, .r2: .fastForward, .start: .back, .select: .action])

    static let builtIns = [standard, classic, fourButtons]
}

/// The profiles, and which one each game uses.
@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var custom: [ControlProfile] = []
    @Published private(set) var assignments: [String: String] = [:]

    private static let customKey = "controls.profiles"
    private static let assignmentKey = "controls.assignments"

    var all: [ControlProfile] { ControlProfile.builtIns + custom }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.customKey),
           let profiles = try? JSONDecoder().decode([ControlProfile].self, from: data) {
            custom = profiles
        }
        assignments = UserDefaults.standard.dictionary(forKey: Self.assignmentKey) as? [String: String] ?? [:]
    }

    /// The profile chosen for the game, or the automatic one: 4 botões
    /// for games with a 4-button or modern controller, Clássico for old
    /// games (Ruby 1.8 / 1.9), Padrão for the rest.
    func profile(for game: GameEntry) -> ControlProfile {
        if let id = assignments[game.id], let chosen = all.first(where: { $0.id == id }) {
            return chosen
        }
        return automaticProfile(for: game)
    }

    func automaticProfile(for game: GameEntry) -> ControlProfile {
        if ControllerTypeStore.type(for: game) != .classic2 { return .fourButtons }
        return game.wantsKeyboardButton ? .classic : .standard
    }

    func isAutomatic(_ game: GameEntry) -> Bool {
        assignments[game.id] == nil
    }

    func assign(_ profile: ControlProfile?, to game: GameEntry) {
        assignments[game.id] = profile?.id
        UserDefaults.standard.set(assignments, forKey: Self.assignmentKey)
    }

    /// A new profile, copied from another, named "<name> (cópia)".
    @discardableResult
    func duplicate(_ profile: ControlProfile) -> ControlProfile {
        var copy = profile
        copy.id = UUID().uuidString
        copy.name = String(localized: "\(profile.name) (cópia)")
        custom.append(copy)
        save()
        return copy
    }

    func update(_ profile: ControlProfile) {
        guard !profile.isBuiltIn, let index = custom.firstIndex(where: { $0.id == profile.id }) else { return }
        custom[index] = profile
        save()
    }

    func delete(_ profile: ControlProfile) {
        custom.removeAll { $0.id == profile.id }
        for (game, id) in assignments where id == profile.id { assignments[game] = nil }
        UserDefaults.standard.set(assignments, forKey: Self.assignmentKey)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: Self.customKey)
        }
    }
}

/// Applies the session's profile: buttons in, game input out.
@MainActor
final class ControlMapper {
    static let shared = ControlMapper()

    var profile: ControlProfile = .standard
    /// Opens Ember's in-game menu (set by the controls overlay).
    var onMenu: (() -> Void)?

    private var counts: [ControlButton: Int] = [:]
    private var active: [ControlButton: GameAction] = [:]

    private init() {}

    func press(_ button: ControlButton) {
        let count = counts[button, default: 0]
        counts[button] = count + 1
        guard count == 0 else { return }
        let action = profile.action(for: button)
        active[button] = action
        if let scancode = action.scancode {
            mkxp_injectKeyEvent(scancode, 1)
            return
        }
        switch action {
        case .emberMenu: onMenu?()
        case .fastForward: mkxp_setFastForwardMultiplier(Int32(AppSettings.fastForwardSpeed))
        case .keyboard: EngineSession.shared.openKeyboard()
        default: break
        }
    }

    func release(_ button: ControlButton) {
        let count = counts[button, default: 0]
        guard count > 0 else { return }
        counts[button] = count - 1
        guard count == 1, let action = active.removeValue(forKey: button) else { return }
        if let scancode = action.scancode {
            mkxp_injectKeyEvent(scancode, 0)
        } else if action == .fastForward {
            GameSettings.apply()
        }
    }

    /// Lets go of everything (session end, controller gone).
    func releaseAll() {
        for button in Array(counts.keys) {
            while counts[button, default: 0] > 0 { release(button) }
        }
    }
}
