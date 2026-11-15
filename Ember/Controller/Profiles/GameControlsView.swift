import SwiftUI

/// Painel do jogo › Controles: what each button does in this game. It
/// starts from a profile; any change becomes the game's own mapping
/// (`ProfileStore.setMapping`). The PC keys found in the game's scripts
/// (`GameKeyStore`) are listed first, each with the button that sends it.
///
/// Two ways to set it up: Simples (each button does a game action) and
/// Teclado (each button and direction presses a PC key, picked on a
/// drawn keyboard), for games made for a computer.
struct GameControlsView: View {
    let game: GameEntry
    @Bindable private var store = ProfileStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var profile: ControlProfile
    @State private var picking: PickTarget?
    private let gameKeys: [KeyboardKey]?

    /// What the keyboard picker is setting.
    private enum PickTarget: Identifiable {
        case button(ControlButton)
        case direction(ControlDirection)

        var id: String {
            switch self {
            case .button(let button): "b.\(button.rawValue)"
            case .direction(let direction): "d.\(direction.rawValue)"
            }
        }
    }

    init(game: GameEntry) {
        self.game = game
        _profile = State(initialValue: ProfileStore.shared.profile(for: game))
        gameKeys = GameKeyStore.keys(for: game.id)
    }

    /// Edits go to the game's own mapping.
    private var editable: Binding<ControlProfile> {
        Binding(get: { profile }, set: { edited in
            profile = edited
            store.setMapping(edited, for: game)
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                baseSection
                if let gameKeys, !gameKeys.isEmpty {
                    keysSection(gameKeys)
                }
                if profile.isKeyboardMode {
                    keyboardButtonsSection
                    directionsSection
                } else {
                    ButtonMappingSection(profile: editable, gameKeys: gameKeys ?? [])
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Controles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .sheet(item: $picking) { target in
                picker(for: target)
                    .presentationDetents([.large])
            }
            #if DEBUG
            .onAppear(perform: developmentHooks)
            #endif
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
                    editable.wrappedValue = edited
                })) {
                Text("Simples").tag(false)
                Text("Teclado").tag(true)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
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
            }
        }
    }

    private var directionsSection: some View {
        Section {
            ForEach(ControlDirection.allCases) { direction in
                Button {
                    picking = .direction(direction)
                } label: {
                    mappingRow(badge: Image(systemName: direction.symbol)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.primaryText)
                                .frame(width: 56, height: 30)
                                .emberGlass(.regular, in: Capsule()),
                               value: profile.key(for: direction).name)
                }
            }
            Menu {
                Button("Setas") { setDirections(\.arrow) }
                Button("W A S D") { setDirections(\.wasd) }
            } label: {
                Label("Usar setas ou WASD", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            }
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
        editable.wrappedValue = edited
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
                           gameKeys: gameKeys ?? [], usedBy: usedBy,
                           specials: [.emberMenu, .fastForward, .keyboard, .none],
                           selectedSpecial: special,
                           onKey: { key in editable.wrappedValue.put(key, on: button) },
                           onSpecial: { action in
                               var edited = profile
                               edited.mapping[button] = action
                               editable.wrappedValue = edited
                           })
        case .direction(let direction):
            KeyboardPicker(title: direction.label, selected: profile.key(for: direction),
                           gameKeys: gameKeys ?? [], usedBy: usedBy,
                           onKey: { key in editable.wrappedValue.put(key, on: direction) })
        }
    }

    // MARK: - Starting profile

    private var baseSection: some View {
        Section {
            Picker("Perfil", selection: Binding(
                get: { store.isAutomatic(game) ? nil : store.baseProfile(for: game).id },
                set: { id in
                    store.assign(store.all.first { $0.id == id }, to: game)
                    profile = store.profile(for: game)
                })) {
                Text("Automático (\(store.automaticProfile(for: game).name))").tag(String?.none)
                ForEach(store.all) { profile in
                    Text(profile.name).tag(String?.some(profile.id))
                }
            }
            if store.hasOwnMapping(game) {
                Button("Desfazer as mudanças deste jogo", role: .destructive) {
                    store.resetMapping(for: game)
                    profile = store.profile(for: game)
                }
            }
        } footer: {
            if store.hasOwnMapping(game) {
                Text("Os botões abaixo foram mudados e valem só para este jogo. Trocar o perfil desfaz as mudanças.")
            } else {
                Text("O jogo começa com este perfil. O que você mudar abaixo vale só para este jogo.")
            }
        }
    }

    // MARK: - Keys the game reads

    private func keysSection(_ keys: [KeyboardKey]) -> some View {
        Section {
            ForEach(keys) { key in
                Menu {
                    Section("Colocar \(key.name) em") {
                        ForEach(ControlButton.allCases) { button in
                            Button {
                                editable.wrappedValue.put(key, on: button)
                            } label: {
                                Text(verbatim: "\(button.label) · \(profile.title(for: button))")
                            }
                        }
                    }
                } label: {
                    keyRow(key)
                }
            }
        } header: {
            Text("Teclas que este jogo usa")
        } footer: {
            Text("Encontradas nos scripts do jogo. Toque numa tecla para colocá-la em um botão. Algumas podem ser só de teste do criador.")
        }
    }

    private func keyRow(_ key: KeyboardKey) -> some View {
        let buttons = profile.buttons(sending: key)
        return HStack(spacing: 12) {
            Text(verbatim: key.name)
                .font(.system(size: key.name.count > 3 ? 12 : 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
                .frame(minWidth: 56, minHeight: 30)
                .padding(.horizontal, key.name.count > 4 ? 8 : 0)
                .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.secondaryText.opacity(0.5)))
            Spacer()
            if buttons.isEmpty {
                Text("Sem botão")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                HStack(spacing: 6) {
                    ForEach(buttons) { ButtonBadge(button: $0) }
                }
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .contentShape(Rectangle())
    }

    #if DEBUG
    /// Development aid: EMBER_CONTROLS=keyboard shows the Teclado mode,
    /// EMBER_CONTROLS=pick also opens the keyboard for the A button.
    private func developmentHooks() {
        guard let mode = ProcessInfo.processInfo.environment["EMBER_CONTROLS"] else { return }
        if !profile.isKeyboardMode {
            var edited = profile
            edited.switchToKeyboard()
            editable.wrappedValue = edited
        }
        if mode == "pick" { picking = .button(.a) }
    }
    #endif
}
