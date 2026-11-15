import SwiftUI

/// The sections that edit a mapping, the same in a game's controls and in
/// a profile: the mode (Simples: each button does a game action; Teclado:
/// each button and direction presses a PC key picked on a drawn
/// keyboard), then the buttons, and in Teclado the directions too.
/// Goes inside a `Form`.
struct ControlMappingEditor: View {
    @Binding var profile: ControlProfile
    /// Keys the game reads, marked on the keyboard and listed first.
    var gameKeys: [KeyboardKey] = []
    /// Ready-made profiles are shown, not edited.
    var disabled = false
    /// Opens the keyboard for this at first (development aid).
    var initialPick: PickTarget?

    @State private var picking: PickTarget?

    /// What the keyboard picker is setting.
    enum PickTarget: Identifiable {
        case button(ControlButton)
        case direction(ControlDirection)

        var id: String {
            switch self {
            case .button(let button): "b.\(button.rawValue)"
            case .direction(let direction): "d.\(direction.rawValue)"
            }
        }
    }

    var body: some View {
        modeSection
        if profile.isKeyboardMode {
            keyboardButtonsSection
            directionsSection
        } else {
            ButtonMappingSection(profile: $profile, gameKeys: gameKeys, disabled: disabled)
        }
    }

    // MARK: - Mode

    private var modeSection: some View {
        Section {
            Picker("Modo", selection: Binding(
                get: { profile.isKeyboardMode },
                set: { keyboard in
                    var edited = profile
                    if keyboard { edited.switchToKeyboard() } else { edited.switchToActions() }
                    profile = edited
                })) {
                Text("Simples").tag(false)
                Text("Teclado").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(disabled)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .sheet(item: $picking) { target in
                picker(for: target)
                    .presentationDetents([.large])
            }
            .onAppear { if let initialPick { picking = initialPick } }
        } footer: {
            if profile.isKeyboardMode {
                Text("Cada botão aperta a tecla do PC que você escolher, como num teclado. Bom para jogos feitos para computador.")
            } else {
                Text("Cada botão faz uma ação do jogo: confirmar, voltar, abrir o menu.")
            }
        }
    }

    // MARK: - Keyboard mode

    private var keyboardButtonsSection: some View {
        Section("Botões") {
            ForEach(ControlButton.allCases) { button in
                Button {
                    picking = .button(button)
                } label: {
                    mappingRow(badge: ButtonBadge(button: button), value: valueTitle(for: button))
                }
                .disabled(disabled)
            }
        }
    }

    private var directionsSection: some View {
        Section {
            ForEach(ControlDirection.allCases) { direction in
                Button {
                    picking = .direction(direction)
                } label: {
                    mappingRow(badge: DirectionBadge(direction: direction),
                               value: profile.key(for: direction).name)
                }
                .disabled(disabled)
            }
            Menu {
                Button("Setas") { setDirections(\.arrow) }
                Button("W A S D") { setDirections(\.wasd) }
            } label: {
                Label("Usar setas ou WASD", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            }
            .disabled(disabled)
        } header: {
            Text("Direcional")
        } footer: {
            Text("O direcional e o analógico apertam estas teclas. A maioria dos jogos anda com as setas.")
        }
    }

    private func mappingRow(badge: some View, value: String) -> some View {
        HStack(spacing: 12) {
            badge
            Text(verbatim: value)
                .foregroundStyle(Theme.primaryText)
            Spacer()
            Image(systemName: "keyboard")
                .foregroundStyle(Theme.secondaryText)
        }
        .contentShape(Rectangle())
    }

    /// The key a button presses, or the Ember action it does.
    private func valueTitle(for button: ControlButton) -> String {
        if let key = profile.pressedKey(for: button) { return key.name }
        return profile.action(for: button).title
    }

    private func setDirections(_ key: KeyPath<ControlDirection, KeyboardKey>) {
        var edited = profile
        for direction in ControlDirection.allCases { edited.put(direction[keyPath: key], on: direction) }
        profile = edited
    }

    /// Button labels on each key, for the drawn keyboard.
    private var usedBy: [Int32: [String]] {
        var used: [Int32: [String]] = [:]
        for button in ControlButton.allCases {
            if let key = profile.pressedKey(for: button) { used[key.scancode, default: []].append(button.shortLabel) }
        }
        // Directions only where they left their arrow (W for ↑).
        for direction in ControlDirection.allCases where profile.key(for: direction) != direction.arrow {
            used[profile.key(for: direction).scancode, default: []].append(direction.arrow.name)
        }
        return used
    }

    @ViewBuilder
    private func picker(for target: PickTarget) -> some View {
        switch target {
        case .button(let button):
            let special = profile.pressedKey(for: button) == nil ? profile.action(for: button) : nil
            KeyboardPicker(title: button.label, selected: profile.pressedKey(for: button),
                           gameKeys: gameKeys, usedBy: usedBy,
                           specials: [.emberMenu, .fastForward, .keyboard, .none],
                           selectedSpecial: special,
                           onKey: { key in profile.put(key, on: button) },
                           onSpecial: { action in profile.mapping[button] = action })
        case .direction(let direction):
            KeyboardPicker(title: direction.label, selected: profile.key(for: direction),
                           gameKeys: gameKeys, usedBy: usedBy,
                           onKey: { key in profile.put(key, on: direction) })
        }
    }

}

/// A direction's arrow in a capsule, next to the button badges.
struct DirectionBadge: View {
    let direction: ControlDirection

    var body: some View {
        Image(systemName: direction.symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.primaryText)
            .frame(width: 56, height: 30)
            .emberGlass(.regular, in: Capsule())
    }
}

extension ControlProfile {
    /// A line for lists: the mode and what the main buttons do.
    var summary: String {
        let buttons: [ControlButton] = [.a, .b, .start, .select]
        if isKeyboardMode {
            let keys = buttons.map { "\($0.label) \(pressedKey(for: $0)?.name ?? action(for: $0).title)" }
            return String(localized: "Teclado") + " · " + keys.joined(separator: " · ")
        }
        return buttons.map { "\($0.label): \(title(for: $0))" }.joined(separator: " · ")
    }
}
