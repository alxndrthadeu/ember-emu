import SwiftUI

/// The Mac tab: Ember on the Mac with the iPhone. Explains how it works,
/// lists the Macs nearby (Ember open: send games; a game open: use the
/// iPhone as its controller) and, once connected, which Mac and game the
/// controller drives.
struct MacTab: View {
    @Bindable private var sender = GameSender.shared
    @Bindable private var client = RemoteControllerClient.shared
    @State private var sending = false

    var body: some View {
        NavigationStack {
            List {
                if case .idle = client.state {} else {
                    connectedSection
                }

                Section {
                    if client.hosts.isEmpty {
                        searching(String(localized: "Abra um jogo no Ember do Mac para ele aparecer aqui."))
                    }
                    ForEach(client.hosts) { host in
                        let parts = host.name.components(separatedBy: " · ")
                        HStack(spacing: 12) {
                            Image(systemName: "gamecontroller.fill")
                                .foregroundStyle(Theme.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: parts.dropFirst().joined(separator: " · ").isEmpty ? host.name : parts.dropFirst().joined(separator: " · "))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.primaryText)
                                    .lineLimit(1)
                                Text(verbatim: parts.first ?? "")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Button("Controlar") {
                                client.connect(to: host)
                                RemoteControllerScreen.present()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                        }
                    }
                } header: {
                    Text("Jogando agora no Mac")
                } footer: {
                    Text("O iPhone vira o controle: botões grandes, sempre deitado, com o menu do jogo (engrenagem) e o teclado. Os botões seguem os controles daquele jogo.")
                }

                Section {
                    if sender.macs.isEmpty {
                        searching(String(localized: "Abra o Ember no Mac."))
                    }
                    ForEach(sender.macs) { mac in
                        HStack(spacing: 12) {
                            Image(systemName: "macbook")
                                .foregroundStyle(Theme.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: mac.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.primaryText)
                                Text("Ember aberto")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Button("Enviar jogos") { sending = true }
                                .buttonStyle(.bordered)
                                .tint(Theme.accent)
                        }
                    }
                } header: {
                    Text("Macs por perto")
                } footer: {
                    Text("Os jogos vão com os saves e os estados salvos. Depois disso, os saves continuam iguais no iPhone e no Mac pelo iCloud.")
                }

                Section {
                    step(1, String(localized: "Abra o Ember no Mac"),
                         String(localized: "O mesmo app, baixado da App Store no Mac. Não precisa estar no mesmo Wi-Fi: o iPhone acha o Mac direto, como no AirDrop."))
                    step(2, String(localized: "Envie seus jogos"),
                         String(localized: "Escolha os jogos em Macs por perto e aceite no Mac. Uma vez basta."))
                    step(3, String(localized: "Jogue no Mac"),
                         String(localized: "Use o teclado, um controle ou este iPhone: abra o jogo no Mac e toque em Controlar."))
                } header: {
                    Text("Como funciona")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Mac")
            .onAppear {
                client.browse()
                sender.browse()
            }
            .sheet(isPresented: $sending) { SendToMacView() }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var connectedSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.title2)
                        .foregroundStyle(statusColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusTitle)
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text(verbatim: client.gameTitle.isEmpty ? hostName : "\(client.gameTitle) · \(hostName)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .lineLimit(2)
                        if case .connected = client.state {
                            Text("\(client.controllerType.title) · velocidade \(client.speed)x")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                HStack {
                    if case .lost = client.state {
                        Button("Reconectar") { client.reconnect() }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                    } else {
                        Button("Abrir o controle") { RemoteControllerScreen.present() }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                    }
                    Button("Desconectar", role: .destructive) { client.disconnect() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Controle")
        }
    }

    private var hostName: String {
        switch client.state {
        case .connecting(let name), .connected(let name), .lost(let name):
            name.components(separatedBy: " · ").first ?? name
        case .idle:
            ""
        }
    }

    private var statusTitle: String {
        switch client.state {
        case .connected: String(localized: "Conectado como controle")
        case .connecting: String(localized: "Conectando…")
        case .lost: String(localized: "Conexão perdida")
        case .idle: ""
        }
    }

    private var statusIcon: String {
        switch client.state {
        case .connected: "checkmark.circle.fill"
        case .connecting: "antenna.radiowaves.left.and.right"
        default: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        if case .connected = client.state { return Theme.activeText }
        return Theme.accent
    }

    private func searching(_ hint: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 2)
    }
}
