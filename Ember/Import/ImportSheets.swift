import SwiftUI

// MARK: - Pieces

/// A small round icon for a road.
struct RoadIcon: View {
    let icon: String
    let tint: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(Circle().fill(tint.opacity(0.16)))
            .accessibilityHidden(true)
    }
}

/// One row of "Outros caminhos".
struct RoadRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    var badge: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoadIcon(icon: icon, tint: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.primaryText)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if let badge {
                    Text(verbatim: badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.activeText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.active.opacity(0.14)))
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheets

struct ImportHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("O que dá para importar") {
                Label("Jogos de RPG Maker XP, VX e VX Ace: .zip, .rar, .7z, .exe autoextraível ou a pasta do jogo", systemImage: "gamecontroller")
                Label("RTP, a pasta com os gráficos e sons padrão", systemImage: "shippingbox")
                Label("Skins .deltaskin e .manicskin", systemImage: "paintpalette")
                Label("Saves pelo painel do jogo, na Biblioteca", systemImage: "externaldrive")
            }
            Section {
                Text("O Ember encontra o jogo mesmo dentro de subpastas. Se quiser, ele manda o arquivo compactado para a lixeira depois de importar, para liberar espaço (Ajustes › Importação).")
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Ajuda")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
    }
}

struct RTPInfoView: View {
    var importAction: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(RTPStore.Kind.allCases) { kind in
                    HStack {
                        Text(kind.name)
                        Spacer()
                        if RTPStore.isInstalled(kind) {
                            Label("Instalado", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(Theme.activeText)
                        } else {
                            Text("Não instalado")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            } footer: {
                Text("Muitos jogos contam com os gráficos e sons padrão do RPG Maker (o RTP), que o Ember não traz. Importe a pasta do RTP, ou um .zip dela, pela aba Importar: o Ember reconhece a versão e todos os jogos dela passam a usar. No Windows, ela fica em Arquivos Comuns › Enterbrain › RGSS.")
            }
            Section {
                Button {
                    importAction()
                } label: {
                    Label("Importar RTP do Arquivos", systemImage: "folder.badge.plus")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("RTP")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
    }
}

/// How to copy games from a computer: the Finder on a Mac, Apple
/// Devices (or iTunes) on Windows; Linux has no Apple app, so it gets
/// the browser transfer, and ifuse for the command line.
struct ComputerInfoView: View {
    var useWifi: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var system = System.mac

    enum System: String, CaseIterable, Identifiable {
        case mac, windows, linux
        var id: String { rawValue }
        var name: String {
            switch self {
            case .mac: "Mac"
            case .windows: "Windows"
            case .linux: "Linux"
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Sistema", selection: $system) {
                    ForEach(System.allCases) { Text(verbatim: $0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            switch system {
            case .mac:
                Section {
                    Step(number: 1, text: String(localized: "Conecte o iPhone ao Mac com o cabo. Depois da primeira vez, o mesmo Wi-Fi basta."))
                    Step(number: 2, text: String(localized: "No Finder, escolha o iPhone na barra lateral e abra a aba Arquivos."))
                    Step(number: 3, text: String(localized: "Arraste o .zip, .rar, .7z ou a pasta do jogo para o Ember."))
                    Step(number: 4, text: String(localized: "Abra o Ember. O jogo aparece na Biblioteca."))
                }
            case .windows:
                Section {
                    Step(number: 1, text: String(localized: "Instale o app Dispositivos Apple pela Microsoft Store (ou use o iTunes)."))
                    Step(number: 2, text: String(localized: "Conecte o iPhone com o cabo e toque em Confiar, se o iPhone perguntar."))
                    Step(number: 3, text: String(localized: "No app, escolha o iPhone e abra Arquivos. Selecione o Ember."))
                    Step(number: 4, text: String(localized: "Arraste o .zip, .rar ou .7z do jogo para o Ember e abra o Ember. O jogo aparece na Biblioteca."))
                } footer: {
                    Text("O Windows não copia pastas por esse caminho: compacte a pasta do jogo num .zip antes, ou use o Wi-Fi.")
                }
            case .linux:
                Section {
                    Text("A Apple não tem app para Linux. O jeito mais fácil é mandar pelo navegador, no mesmo Wi-Fi: funciona com arquivos e pastas inteiras.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                    Button {
                        useWifi()
                    } label: {
                        Label("Ligar o envio pelo Wi-Fi", systemImage: "wifi")
                    }
                }
                Section {
                    Text(verbatim: "ifuse --documents \(Bundle.main.bundleIdentifier ?? "com.alexandrethadeu.ember") ~/ember")
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text("Pelo terminal, com cabo")
                } footer: {
                    Text("Com libimobiledevice e ifuse instalados, esse comando monta a pasta do Ember. Copie o jogo para dentro dela, desmonte com fusermount -u ~/ember e abra o Ember.")
                }
            }

            Section {
            } footer: {
                Text("No Safari, no Arquivos ou num app de mensagens também dá: toque no arquivo, depois em Compartilhar e em Ember.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Do computador")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.accent))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Item providers (clipboard, drag and drop)
