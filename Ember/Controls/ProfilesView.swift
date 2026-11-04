import SwiftUI

/// Ajustes › Perfis de controle: the ready-made profiles and the
/// player's own.
struct ProfilesView: View {
    @ObservedObject private var store = ProfileStore.shared
    @State private var editing: ControlProfile?

    var body: some View {
        List {
            Section {
                ForEach(ControlProfile.builtIns) { profile in
                    NavigationLink {
                        ProfileEditor(profile: profile)
                    } label: {
                        ProfileRow(profile: profile)
                    }
                }
            } header: {
                Text("Prontos")
            } footer: {
                Text("Padrão serve para Pokémon Essentials v19 ou mais novo e jogos em Ruby 3. Clássico serve para jogos antigos: Start abre o menu e segurar Select faz correr. Cada jogo usa um deles automaticamente, e você pode trocar no painel do jogo.")
            }

            Section("Seus perfis") {
                ForEach(store.custom) { profile in
                    NavigationLink {
                        ProfileEditor(profile: profile)
                    } label: {
                        ProfileRow(profile: profile)
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
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Perfis de controle")
        .navigationDestination(item: $editing) { profile in
            ProfileEditor(profile: profile)
        }
    }
}

private struct ProfileRow: View {
    let profile: ControlProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(profile.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text(summary)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
    }

    private var summary: String {
        [ControlButton.a, .b, .start, .select]
            .map { "\($0.label): \(profile.action(for: $0).title)" }
            .joined(separator: " · ")
    }
}

/// One profile's buttons. Ready-made profiles are read-only; "Duplicar"
/// makes an editable copy.
struct ProfileEditor: View {
    @ObservedObject private var store = ProfileStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var profile: ControlProfile
    @State private var copy: ControlProfile?

    init(profile: ControlProfile) {
        _profile = State(initialValue: profile)
    }

    var body: some View {
        Form {
            if !profile.isBuiltIn {
                Section("Nome") {
                    TextField("Nome do perfil", text: $profile.name)
                }
            }
            section("Na tela e no controle", buttons: ControlButton.allCases.filter(\.isOnScreen))
            section("Só no controle", buttons: ControlButton.allCases.filter { !$0.isOnScreen })

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
                    Button("Apagar perfil", role: .destructive) {
                        store.delete(profile)
                        dismiss()
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

    private func section(_ title: String, buttons: [ControlButton]) -> some View {
        Section(title) {
            ForEach(buttons) { button in
                Picker(selection: Binding(
                    get: { profile.action(for: button) },
                    set: { profile.mapping[button] = $0 })
                ) {
                    ForEach(GameAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(button.label)
                            .font(.system(size: button.label.count > 2 ? 11 : 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 56, height: 30)
                            .glassEffect(.regular, in: Capsule())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.action(for: button).title)
                                .foregroundStyle(Theme.primaryText)
                            Text(profile.action(for: button).detail)
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(2)
                        }
                    }
                }
                .pickerStyle(.navigationLink)
                .disabled(profile.isBuiltIn)
            }
        }
    }
}
