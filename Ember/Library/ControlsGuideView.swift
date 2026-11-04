import SwiftUI

/// What each button does, on the screen and on a controller. Mirrors
/// GameKey (on-screen) and the engine's default controller bindings
/// (src/input/keybindings.cpp in the engine).
struct ControlsGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ControlRow(symbol: "dpad.fill", name: "Direcional", action: "Andar e navegar nos menus")
                    ControlRow(label: "A", name: "A", action: "Confirmar, falar, interagir")
                    ControlRow(label: "B", name: "B", action: "Voltar. Segure para correr")
                    ControlRow(label: "START", name: "Start", action: "Abrir o menu do jogo")
                    ControlRow(label: "SELECT", name: "Select", action: "Menu rápido (itens registrados)")
                    ControlRow(label: "L R", name: "L e R", action: "Atalhos que o jogo definir")
                    ControlRow(symbol: "gearshape.fill", name: "Engrenagem", action: "Pausa: velocidade, captura, sair")
                } header: {
                    Text("Na tela")
                } footer: {
                    Text("Vale para jogos com Pokémon Essentials v19 ou mais novo. Em jogos mais antigos, o B costuma abrir o menu e segurar Start faz correr.")
                }

                Section {
                    ControlRow(label: "A", name: "A / Cruz", action: "Confirmar")
                    ControlRow(label: "B", name: "B / Círculo", action: "Voltar. Segure para correr")
                    ControlRow(label: "X", name: "X / Quadrado", action: "Abrir o menu do jogo")
                    ControlRow(label: "Y", name: "Y / Triângulo", action: "Ação extra do jogo")
                    ControlRow(label: "LB RB", name: "LB e RB", action: "L e R")
                    ControlRow(symbol: "l.joystick.fill", name: "Direcional e analógico", action: "Andar")
                } header: {
                    Text("Controle físico")
                } footer: {
                    Text("Controles de Xbox, PlayStation e MFi funcionam assim que conectados. Personalizar os botões chega numa próxima versão.")
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
            .frame(width: 44, height: 32)
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
