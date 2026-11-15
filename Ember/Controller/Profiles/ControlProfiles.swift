import Observation
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

    /// Two letters at most, for the corner of a keycap.
    var shortLabel: String {
        switch self {
        case .l2: "L2"
        case .r2: "R2"
        case .start: "ST"
        case .select: "SE"
        default: label
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

/// A direction of the D-pad or stick. It presses its arrow key, or the
/// key the game's keyboard mapping gives it.
enum ControlDirection: String, Codable, CaseIterable, Identifiable {
    case up, down, left, right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .up: String(localized: "Cima")
        case .down: String(localized: "Baixo")
        case .left: String(localized: "Esquerda")
        case .right: String(localized: "Direita")
        }
    }

    var symbol: String {
        switch self {
        case .up: "arrowtriangle.up.fill"
        case .down: "arrowtriangle.down.fill"
        case .left: "arrowtriangle.left.fill"
        case .right: "arrowtriangle.right.fill"
        }
    }

    init?(_ key: GameKey) {
        switch key {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        default: return nil
        }
    }

    var arrow: KeyboardKey {
        switch self {
        case .up: KeyboardKey(scancode: 82)
        case .down: KeyboardKey(scancode: 81)
        case .left: KeyboardKey(scancode: 80)
        case .right: KeyboardKey(scancode: 79)
        }
    }

    /// W, S, A, D.
    var wasd: KeyboardKey {
        switch self {
        case .up: KeyboardKey(scancode: 26)
        case .down: KeyboardKey(scancode: 22)
        case .left: KeyboardKey(scancode: 4)
        case .right: KeyboardKey(scancode: 7)
        }
    }
}

/// What a button does. Game actions are RGSS buttons, sent as the keys
/// the engine's default bindings read (GameKey has the full table).
enum GameAction: String, Codable, CaseIterable, Identifiable {
    case confirm, back, action, special, x, y, l, r
    case emberMenu, fastForward, keyboard, none
    /// Any PC key, chosen per button (ControlProfile.keys).
    case key

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
        case .key: String(localized: "Tecla do teclado")
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
        case .key: String(localized: "Uma tecla do PC, para jogos que usam números ou letras")
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
    /// The key of each button set to "Tecla do teclado" (absent in
    /// profiles saved before 1.2).
    var keys: [ControlButton: KeyboardKey]? = nil
    /// Shown as a PC keyboard: every button is a key (Teclado mode of
    /// the game's controls screen). Only how the screen shows it; the
    /// mapping above is what plays.
    var keyboardMode: Bool? = nil
    /// Keys the D-pad presses instead of the arrows.
    var directionKeys: [ControlDirection: KeyboardKey]? = nil

    var isBuiltIn: Bool { id.hasPrefix("builtin.") }

    var isKeyboardMode: Bool { keyboardMode ?? false }

    func key(for direction: ControlDirection) -> KeyboardKey {
        directionKeys?[direction] ?? direction.arrow
    }

    mutating func put(_ key: KeyboardKey, on direction: ControlDirection) {
        var keys = directionKeys ?? [:]
        keys[direction] = key == direction.arrow ? nil : key
        directionKeys = keys.isEmpty ? nil : keys
    }

    /// The key a button presses, for the keyboard view: its own key, or
    /// the one its game action sends (Enter for Confirmar).
    func pressedKey(for button: ControlButton) -> KeyboardKey? {
        scancode(for: button).map(KeyboardKey.init(scancode:))
    }

    /// Every button as the key it already sends, so switching to the
    /// keyboard view changes nothing until the player does.
    mutating func switchToKeyboard() {
        for button in ControlButton.allCases {
            if action(for: button) != .key, let key = pressedKey(for: button) { put(key, on: button) }
        }
        keyboardMode = true
    }

    /// Keys that are a game action's key go back to that action.
    mutating func switchToActions() {
        let actions = GameAction.allCases.filter { $0.scancode != nil }
        for button in ControlButton.allCases where action(for: button) == .key {
            if let action = actions.first(where: { $0.scancode == key(for: button).scancode }) {
                mapping[button] = action
                keys?[button] = nil
            }
        }
        keyboardMode = nil
    }

    func key(for button: ControlButton) -> KeyboardKey {
        keys?[button] ?? .space
    }

    /// The key a button sends, if its action is a key.
    func scancode(for button: ControlButton) -> Int32? {
        let action = action(for: button)
        return action == .key ? key(for: button).scancode : action.scancode
    }

    /// What a button does, for lists: the key's name for "Tecla do teclado".
    func title(for button: ControlButton) -> String {
        let action = action(for: button)
        return action == .key ? String(localized: "Tecla \(key(for: button).name)") : action.title
    }

    func action(for button: ControlButton) -> GameAction {
        mapping[button] ?? .none
    }

    /// The buttons that press this key, by its own action or as a game
    /// button bound to it (Enter for Confirmar).
    func buttons(sending key: KeyboardKey) -> [ControlButton] {
        ControlButton.allCases.filter { scancode(for: $0) == key.scancode }
    }

    /// Puts the key on a button ("Tecla do teclado").
    mutating func put(_ key: KeyboardKey, on button: ControlButton) {
        mapping[button] = .key
        var keys = self.keys ?? [:]
        keys[button] = key
        self.keys = keys
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

/// The profiles, and which one each game uses. A game can also have its
/// own mapping, edited in its controls screen: a copy of its profile
/// that only that game uses.
@MainActor
@Observable
final class ProfileStore {
    static let shared = ProfileStore()

    private(set) var custom: [ControlProfile] = []
    private(set) var assignments: [String: String] = [:]
    /// Own mappings, by game id.
    private(set) var gameMappings: [String: ControlProfile] = [:]

    private static let customKey = "controls.profiles"
    private static let assignmentKey = "controls.assignments"
    private static let gameMappingKey = "controls.gameMappings"

    var all: [ControlProfile] { ControlProfile.builtIns + custom }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.customKey),
           let profiles = try? JSONDecoder().decode([ControlProfile].self, from: data) {
            custom = profiles
        }
        assignments = UserDefaults.standard.dictionary(forKey: Self.assignmentKey) as? [String: String] ?? [:]
        if let data = UserDefaults.standard.data(forKey: Self.gameMappingKey),
           let mappings = try? JSONDecoder().decode([String: ControlProfile].self, from: data) {
            gameMappings = mappings
        }
    }

    /// What the game plays with: its own mapping, or its profile.
    func profile(for game: GameEntry) -> ControlProfile {
        gameMappings[game.id] ?? baseProfile(for: game)
    }

    /// The profile chosen for the game, or the automatic one: 4 botões
    /// for games with a 4-button or modern controller, Clássico for old
    /// games (Ruby 1.8 / 1.9), Padrão for the rest.
    func baseProfile(for game: GameEntry) -> ControlProfile {
        if let id = assignments[game.id], let chosen = all.first(where: { $0.id == id }) {
            return chosen
        }
        return automaticProfile(for: game)
    }

    func hasOwnMapping(_ game: GameEntry) -> Bool {
        gameMappings[game.id] != nil
    }

    /// Saves the game's own mapping (and uses it now if the game is open).
    func setMapping(_ profile: ControlProfile, for game: GameEntry) {
        var own = profile
        own.id = "game.\(game.id)"
        own.name = game.title
        gameMappings[game.id] = own
        saveMappings()
        applyIfPlaying(game)
    }

    /// Back to the game's profile.
    func resetMapping(for game: GameEntry) {
        gameMappings[game.id] = nil
        saveMappings()
        applyIfPlaying(game)
    }

    func automaticProfile(for game: GameEntry) -> ControlProfile {
        if ControllerTypeStore.type(for: game) != .classic2 { return .fourButtons }
        return game.wantsKeyboardButton ? .classic : .standard
    }

    func isAutomatic(_ game: GameEntry) -> Bool {
        assignments[game.id] == nil
    }

    /// Picks the game's profile; its own mapping, if any, gives way.
    func assign(_ profile: ControlProfile?, to game: GameEntry) {
        assignments[game.id] = profile?.id
        UserDefaults.standard.set(assignments, forKey: Self.assignmentKey)
        gameMappings[game.id] = nil
        saveMappings()
        applyIfPlaying(game)
    }

    private func applyIfPlaying(_ game: GameEntry) {
        guard EngineSession.shared.currentGame?.id == game.id else { return }
        ControlMapper.shared.releaseAll()
        ControlMapper.shared.profile = profile(for: game)
    }

    private func saveMappings() {
        if let data = try? JSONEncoder().encode(gameMappings) {
            UserDefaults.standard.set(data, forKey: Self.gameMappingKey)
        }
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
    private var activeKeys: [ControlButton: Int32] = [:]
    private var directionCounts: [ControlDirection: Int] = [:]
    private var activeDirections: [ControlDirection: Int32] = [:]

    private init() {}

    /// A direction from the D-pad, stick or a controller: its arrow, or
    /// the key the game's mapping gives it. Counted, as two sources can
    /// hold the same direction.
    func press(_ direction: ControlDirection) {
        let count = directionCounts[direction, default: 0]
        directionCounts[direction] = count + 1
        guard count == 0 else { return }
        let scancode = profile.key(for: direction).scancode
        activeDirections[direction] = scancode
        mkxp_injectKeyEvent(scancode, 1)
    }

    func release(_ direction: ControlDirection) {
        let count = directionCounts[direction, default: 0]
        guard count > 0 else { return }
        directionCounts[direction] = count - 1
        guard count == 1, let scancode = activeDirections.removeValue(forKey: direction) else { return }
        mkxp_injectKeyEvent(scancode, 0)
    }

    func press(_ button: ControlButton) {
        let count = counts[button, default: 0]
        counts[button] = count + 1
        guard count == 0 else { return }
        let action = profile.action(for: button)
        active[button] = action
        if let scancode = profile.scancode(for: button) {
            activeKeys[button] = scancode
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
        // The key pressed, even if the profile changed meanwhile.
        if let scancode = activeKeys.removeValue(forKey: button) {
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
        for direction in Array(directionCounts.keys) {
            while directionCounts[direction, default: 0] > 0 { release(direction) }
        }
    }
}
