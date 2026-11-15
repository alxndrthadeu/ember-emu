import SwiftUI

/// Painel do jogo › Controles: what each button does in this game. It
/// starts from a profile; any change becomes the game's own mapping
/// (`ProfileStore.setMapping`). The PC keys found in the game's scripts
/// (`GameKeyStore`) are listed first, each with the button that sends it.
struct GameControlsView: View {
    let game: GameEntry
    @Bindable private var store = ProfileStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var profile: ControlProfile
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
                ButtonMappingSection(profile: editable, gameKeys: gameKeys ?? [])
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
}
