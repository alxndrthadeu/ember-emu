import SwiftUI

/// Painel do jogo › Controles: what each button does in this game. It
/// starts from a profile; any change becomes the game's own mapping
/// (`ProfileStore.setMapping`), which can be saved as a profile for
/// other games. The PC keys found in the game's scripts (`GameKeyStore`)
/// are listed first, each with the button that sends it. The mapping
/// itself is edited by `ControlMappingEditor`, as in a profile.
struct GameControlsView: View {
    let game: GameEntry
    @Bindable private var store = ProfileStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var profile: ControlProfile
    @State private var naming = false
    @State private var newName = ""
    @State private var savedName: String?
    @State private var confirmingReset = false
    private let gameKeys: [KeyboardKey]?

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
                baseSection
                if let gameKeys, !gameKeys.isEmpty {
                    keysSection(gameKeys)
                }
                ControlMappingEditor(profile: editable, gameKeys: gameKeys ?? [], initialPick: developmentPick)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Controles deste jogo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .alert("Salvar como perfil", isPresented: $naming) {
                TextField("Nome do perfil", text: $newName)
                Button("Cancelar", role: .cancel) {}
                Button("Salvar") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard let saved = store.saveAsProfile(game, name: name.isEmpty ? game.title : name) else { return }
                    profile = saved
                    savedName = saved.name
                }
            } message: {
                Text("O perfil aparece em Ajustes › Perfis de controle e pode ser usado em outros jogos.")
            }
            #if DEBUG
            .onAppear(perform: developmentHooks)
            #endif
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
                    savedName = nil
                })) {
                Text("Automático (\(store.automaticProfile(for: game).name))").tag(String?.none)
                ForEach(store.all) { profile in
                    Text(profile.name).tag(String?.some(profile.id))
                }
            }
            if store.hasOwnMapping(game) {
                Button {
                    newName = game.title
                    naming = true
                } label: {
                    Label("Salvar como perfil", systemImage: "square.and.arrow.down")
                }
                Button("Desfazer as mudanças deste jogo", role: .destructive) {
                    confirmingReset = true
                }
                .confirmationDialog("Desfazer as mudanças deste jogo?", isPresented: $confirmingReset,
                                    titleVisibility: .visible) {
                    Button("Desfazer as mudanças", role: .destructive) {
                        store.resetMapping(for: game)
                        profile = store.profile(for: game)
                    }
                } message: {
                    Text("Os botões voltam a ser os do perfil “\(store.baseProfile(for: game).name)”.")
                }
            }
        } footer: {
            if let savedName {
                Text("Salvo como “\(savedName)”. Este jogo agora usa esse perfil; mudanças aqui viram de novo só deste jogo.")
            } else if store.hasOwnMapping(game) {
                Text("Os botões abaixo foram mudados e valem só para este jogo. Salve como perfil para usar em outros jogos, ou troque o perfil para desfazer.")
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
                .font(key.name.count > 3 ? .caption.weight(.bold) : .subheadline.weight(.bold))
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

    // MARK: - Development

    /// EMBER_CONTROLS=keyboard shows the Teclado mode; =pick also opens
    /// the keyboard for the A button.
    private var developmentPick: ControlMappingEditor.PickTarget? {
        #if DEBUG
        ProcessInfo.processInfo.environment["EMBER_CONTROLS"] == "pick" ? .button(.a) : nil
        #else
        nil
        #endif
    }

    #if DEBUG
    private func developmentHooks() {
        guard ProcessInfo.processInfo.environment["EMBER_CONTROLS"] != nil, !profile.isKeyboardMode else { return }
        var edited = profile
        edited.switchToKeyboard()
        editable.wrappedValue = edited
    }
    #endif
}
