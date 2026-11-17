import SwiftUI

/// Ajustes › Perfis de controle: every mapping in one place. The
/// player's profiles, the ready-made ones, and the games with their own
/// controls (which can become a profile). Each profile says which games
/// use it.
struct ProfilesView: View {
    @Bindable private var store = ProfileStore.shared
    @Bindable private var library = LibraryStore.shared
    @State private var editing: ControlProfile?
    @State private var gameControls: GameEntry?
    @State private var naming: GameEntry?
    @State private var newName = ""

    private var gamesWithOwn: [GameEntry] {
        library.games.filter(store.hasOwnMapping)
    }

    var body: some View {
        List {
            Section {
                ForEach(store.custom) { profile in
                    NavigationLink {
                        ProfileEditor(profile: profile)
                    } label: {
                        ProfileRow(profile: profile, games: store.games(using: profile, in: library.games))
                    }
                }
                .onDelete { offsets in
                    offsets.map { store.custom[$0] }.forEach(store.delete)
                }
                Button {
                    editing = store.duplicate(.standard)
                } label: {
                    Label("Novo perfil", systemImage: "plus")
                }
            } header: {
                Text("Seus perfis")
            } footer: {
                Text("Crie aqui ou salve os controles de um jogo como perfil. Escolha o perfil de cada jogo no painel do jogo › Controles.")
            }

            if !gamesWithOwn.isEmpty {
                Section {
                    ForEach(gamesWithOwn) { game in
                        Button {
                            gameControls = game
                        } label: {
                            HStack {
                                ProfileRow(profile: store.profile(for: game), title: game.title, games: [])
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.secondaryText.opacity(0.6))
                            }
                        }
                        .swipeActions {
                            Button {
                                newName = game.title
                                naming = game
                            } label: {
                                Label("Salvar como perfil", systemImage: "square.and.arrow.down")
                            }
                            .tint(Theme.active)
                        }
                        .contextMenu {
                            Button {
                                newName = game.title
                                naming = game
                            } label: {
                                Label("Salvar como perfil", systemImage: "square.and.arrow.down")
                            }
                        }
                    }
                } header: {
                    Text("Controles de jogos")
                } footer: {
                    Text("Jogos com botões mudados só para eles. Deslize para salvar como perfil e usar em outros jogos.")
                }
            }

            Section {
                ForEach(ControlProfile.builtIns) { profile in
                    NavigationLink {
                        ProfileEditor(profile: profile)
                    } label: {
                        ProfileRow(profile: profile, games: store.games(using: profile, in: library.games))
                    }
                }
            } header: {
                Text("Prontos")
            } footer: {
                Text("Padrão serve para Pokémon Essentials v19 ou mais novo e jogos em Ruby 3. Clássico serve para jogos antigos: Start abre o menu e segurar Select faz correr. 4 botões usa X e Y do jogo. Cada jogo usa um deles automaticamente.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Perfis de controle")
        .navigationDestination(item: $editing) { profile in
            ProfileEditor(profile: profile)
        }
        .sheet(item: $gameControls) { game in
            GameControlsView(game: game)
        }
        .alert("Salvar como perfil", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Nome do perfil", text: $newName)
            Button("Cancelar", role: .cancel) {}
            Button("Salvar") {
                guard let game = naming else { return }
                let name = newName.trimmingCharacters(in: .whitespaces)
                store.saveAsProfile(game, name: name.isEmpty ? game.title : name)
            }
        } message: {
            Text("O jogo passa a usar o perfil novo, e outros jogos também podem usá-lo.")
        }
    }
}

/// A profile in a list: its name, what the main buttons do, and the games
/// that use it.
private struct ProfileRow: View {
    let profile: ControlProfile
    var title: String?
    let games: [GameEntry]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: profile.isKeyboardMode ? "keyboard" : "gamecontroller")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title ?? profile.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(verbatim: profile.summary)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                if !games.isEmpty {
                    Text(usedIn)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.activeText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var usedIn: String {
        games.count == 1
            ? String(localized: "Usado em \(games[0].title)")
            : String(localized: "Usado em \(games.count) jogos")
    }
}

/// One profile: its name, its mapping (the same editor as a game's
/// controls) and the games that use it. Ready-made profiles are
/// read-only; "Duplicar" makes an editable copy.
struct ProfileEditor: View {
    @Bindable private var store = ProfileStore.shared
    @Bindable private var library = LibraryStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var profile: ControlProfile
    @State private var copy: ControlProfile?
    @State private var confirmingDelete = false

    init(profile: ControlProfile) {
        _profile = State(initialValue: profile)
    }

    var body: some View {
        let games = store.games(using: profile, in: library.games)
        Form {
            if !profile.isBuiltIn {
                Section("Nome") {
                    TextField("Nome do perfil", text: $profile.name)
                }
            }
            ControlMappingEditor(profile: $profile, disabled: profile.isBuiltIn)

            if !games.isEmpty {
                Section("Jogos com este perfil") {
                    ForEach(games) { game in
                        Text(verbatim: game.title)
                            .foregroundStyle(Theme.primaryText)
                    }
                }
            }

            if profile.isBuiltIn {
                Section {
                    Button {
                        copy = store.duplicate(profile)
                    } label: {
                        Label("Duplicar para editar", systemImage: "plus.square.on.square")
                    }
                } footer: {
                    Text("Os perfis prontos não mudam. Duplique para criar o seu a partir deste.")
                }
            } else {
                Section {
                    Button {
                        copy = store.duplicate(profile)
                    } label: {
                        Label("Duplicar", systemImage: "plus.square.on.square")
                    }
                    Button("Apagar perfil", role: .destructive) {
                        confirmingDelete = true
                    }
                    .confirmationDialog("Apagar “\(profile.name)”?", isPresented: $confirmingDelete,
                                        titleVisibility: .visible) {
                        Button("Apagar perfil", role: .destructive) {
                            store.delete(profile)
                            dismiss()
                        }
                    } message: {
                        if games.isEmpty {
                            Text("O perfil sai da lista. Isso não pode ser desfeito.")
                        } else {
                            Text("Os jogos com este perfil voltam ao automático. Isso não pode ser desfeito.")
                        }
                    }
                } footer: {
                    if !games.isEmpty {
                        Text("Os jogos com este perfil voltam ao automático se ele for apagado.")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: profile) { store.update(profile) }
        .navigationDestination(item: $copy) { ProfileEditor(profile: $0) }
    }
}

/// Each button and what it does, editable: an action, or a PC key. The
/// keys a game was found to use (`gameKeys`) come first in the key list.
struct ButtonMappingSection: View {
    @Binding var profile: ControlProfile
    var gameKeys: [KeyboardKey] = []
    var disabled = false

    var body: some View {
        Section(String(localized: "Botões")) {
            ForEach(ControlButton.allCases) { button in
                Picker(selection: Binding(
                    get: { profile.action(for: button) },
                    set: { profile.mapping[button] = $0 })
                ) {
                    ForEach(GameAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                } label: {
                    HStack(spacing: 12) {
                        ButtonBadge(button: button)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.title(for: button))
                                .foregroundStyle(Theme.primaryText)
                            Text(profile.action(for: button).detail)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(2)
                        }
                    }
                }
                .pickerStyle(.navigationLink)
                .disabled(disabled)
                if profile.action(for: button) == .key {
                    Picker(String(localized: "Tecla"), selection: Binding(
                        get: { profile.key(for: button) },
                        set: { profile.put($0, on: button) })) {
                        if gameKeys.isEmpty {
                            ForEach(KeyboardKey.all) { Text(verbatim: $0.name).tag($0) }
                        } else {
                            Section("Usadas por este jogo") {
                                ForEach(gameKeys) { Text(verbatim: $0.name).tag($0) }
                            }
                            Section("Todas as teclas") {
                                ForEach(KeyboardKey.all.filter { !gameKeys.contains($0) }) {
                                    Text(verbatim: $0.name).tag($0)
                                }
                            }
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .disabled(disabled)
                    .padding(.leading, 68)
                }
            }
        }
    }
}

/// A button's name in a capsule, as in the profile lists.
struct ButtonBadge: View {
    let button: ControlButton
    // Grow with the text size (Dynamic Type).
    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 56
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var large: CGFloat = 15
    @ScaledMetric(relativeTo: .body) private var small: CGFloat = 11

    var body: some View {
        Text(button.label)
            .font(.system(size: button.label.count > 2 ? small : large, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.primaryText)
            .frame(width: width, height: height)
            .emberGlass(.regular, in: Capsule())
    }
}
