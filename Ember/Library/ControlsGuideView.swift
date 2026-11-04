import SwiftUI

/// What each button does, read from the control profiles.
struct ControlsGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ProfileStore.shared
    @State private var profileID = ControlProfile.standard.id

    private var profile: ControlProfile {
        store.all.first { $0.id == profileID } ?? .standard
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Perfil", selection: $profileID) {
                        ForEach(store.all) { Text($0.name).tag($0.id) }
                    }
                } footer: {
                    Text("Cada jogo usa Padrão ou Clássico automaticamente (Clássico nos jogos antigos). Troque no painel do jogo, segurando a capa, ou crie o seu em Ajustes › Perfis de controle.")
                }

                Section("Na tela") {
                    ControlRow(symbol: "dpad.fill", name: "Direcional", action: "Andar e navegar nos menus")
                    ForEach(ControlButton.allCases.filter(\.isOnScreen)) { button in
                        ControlRow(label: button.label.uppercased(), name: button.label,
                                   action: profile.action(for: button).title)
                    }
                    ControlRow(symbol: "gearshape.fill", name: "Engrenagem", action: "Pausa: velocidade, captura, teclado, sair")
                    ControlRow(symbol: "keyboard.fill", name: "Teclado", action: "Aparece nos jogos antigos, para digitar nomes")
                }

                Section {
                    ControlRow(symbol: "l.joystick.fill", name: "Direcional e analógico", action: "Andar")
                    ForEach(ControlButton.allCases) { button in
                        ControlRow(label: button.label.uppercased(), name: physicalName(button),
                                   action: profile.action(for: button).title)
                    }
                } header: {
                    Text("Controle físico")
                } footer: {
                    Text("Controles de Xbox, PlayStation e MFi funcionam assim que conectados e seguem o perfil do jogo.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Controles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Fechar")
                }
            }
        }
    }

    private func physicalName(_ button: ControlButton) -> String {
        switch button {
        case .a: "A / Cruz"
        case .b: "B / Círculo"
        case .x: "X / Quadrado"
        case .y: "Y / Triângulo"
        case .l: "LB / L1"
        case .r: "RB / R1"
        case .l2: "LT / L2"
        case .r2: "RT / R2"
        case .start: "Menu / Options"
        case .select: "View / Create"
        }
    }
}

private struct ControlRow: View {
    var symbol: String?
    var label: String?
    let name: String
    let action: String

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                } else {
                    Text(label ?? "")
                        .font(.system(size: (label?.count ?? 0) > 2 ? 9 : 15, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(Theme.primaryText)
            .frame(width: 48, height: 32)
            .glassEffect(.regular, in: Capsule())

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(action)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .listRowBackground(Theme.surface)
    }
}
