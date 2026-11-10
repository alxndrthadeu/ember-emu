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
                    ControlRow(symbol: "dpad.fill", name: String(localized: "Direcional"), action: String(localized: "Andar e navegar nos menus"))
                    ForEach(ControlButton.allCases) { button in
                        ControlRow(label: button.label.uppercased(), name: button.label,
                                   action: profile.title(for: button))
                    }
                    ControlRow(symbol: "gearshape.fill", name: String(localized: "Engrenagem"), action: String(localized: "Pausa: velocidade, captura, teclado, sair"))
                    ControlRow(symbol: "keyboard.fill", name: String(localized: "Teclado"), action: String(localized: "Aparece nos jogos antigos, para digitar nomes"))
                }

                Section {
                    ControlRow(symbol: "l.joystick.fill", name: String(localized: "Direcional e analógico"), action: String(localized: "Andar"))
                    ForEach(ControlButton.allCases) { button in
                        ControlRow(label: button.label.uppercased(), name: physicalName(button),
                                   action: profile.title(for: button))
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
        case .a: String(localized: "A / Cruz")
        case .b: String(localized: "B / Círculo")
        case .x: String(localized: "X / Quadrado")
        case .y: String(localized: "Y / Triângulo")
        case .l: "LB / L1"
        case .r: "RB / R1"
        case .l2: "LT / L2"
        case .r2: "RT / R2"
        case .start: String(localized: "Menu / Options")
        case .select: String(localized: "View / Create")
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
            .emberGlass(.regular, in: Capsule())

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
