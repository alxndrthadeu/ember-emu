import SwiftUI

/// A game's saves in iCloud, side by side with this device's, like a
/// console's cloud storage: which is newer, who saved it, and the two
/// moves by hand, send everything up or bring everything down. Also
/// whether the game syncs on its own. Shared by the iPhone and the Mac.
struct CloudSavesView: View {
    let game: GameEntry
    /// The library reloads after saves came down.
    var onChange: () -> Void = {}

    @State private var here: SaveSync.Side?
    @State private var there: SaveSync.Side?
    @State private var noCloud = false
    @State private var automatic: Bool
    @State private var working: Move?
    @State private var confirming: Move?
    @State private var message: String?

    enum Move: Identifiable {
        case send, bring
        var id: Self { self }
    }

    init(game: GameEntry, onChange: @escaping () -> Void = {}) {
        self.game = game
        self.onChange = onChange
        _automatic = State(initialValue: SaveSync.syncsAutomatically(game.id))
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    SideCard(title: CloudSavesView.deviceTitle, icon: CloudSavesView.deviceIcon,
                             side: here, newer: newer == .send)
                    SideCard(title: String(localized: "No iCloud"), icon: "icloud",
                             side: noCloud ? SaveSync.Side() : there, newer: newer == .bring,
                             unavailable: noCloud)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                Toggle("Sincronizar automaticamente", isOn: $automatic)
                    .disabled(!SaveSync.isEnabled)
                    .onChange(of: automatic) {
                        SaveSync.setSyncsAutomatically(automatic, for: game.id)
                    }
            } footer: {
                if SaveSync.isEnabled {
                    Text("Ligado, cada save vai para o iCloud assim que o jogo salva, e o que outro aparelho mandou chega antes de abrir o jogo. Desligado, só quando você enviar ou baixar aqui.")
                } else {
                    Text("A sincronização automática está desligada para todos os jogos, em Ajustes.")
                }
            }

            Section {
                Button {
                    confirming = .send
                } label: {
                    HStack {
                        Label("Enviar para o iCloud", systemImage: "icloud.and.arrow.up")
                        Spacer()
                        if working == .send { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(working != nil || noCloud || here?.isEmpty != false)

                Button {
                    confirming = .bring
                } label: {
                    HStack {
                        Label("Baixar do iCloud", systemImage: "icloud.and.arrow.down")
                        Spacer()
                        if working == .bring { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(working != nil || noCloud || there?.isEmpty != false || isPlaying)
            } footer: {
                if isPlaying {
                    Text("Feche o jogo para baixar saves do iCloud.")
                } else {
                    Text("Enviar troca os saves do iCloud pelos deste aparelho; baixar faz o contrário. O que for substituído fica guardado em Backups.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(game.title)
        .task { await load() }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirming != nil },
                                                               set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { move in
            Button(move == .send ? String(localized: "Enviar") : String(localized: "Baixar")) {
                Task { await run(move) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { move in
            if move == .send {
                Text("Os saves deste jogo no iCloud passam a ser os deste aparelho. Os de lá ficam em Backups.")
            } else {
                Text("Os saves deste jogo neste aparelho passam a ser os do iCloud. Os daqui ficam em Backups.")
            }
        }
        .alert("Saves no iCloud", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    // MARK: -

    private var confirmTitle: String {
        confirming == .send ? String(localized: "Enviar os saves para o iCloud?")
                            : String(localized: "Baixar os saves do iCloud?")
    }

    /// Which side has the newest save, when they differ.
    private var newer: Move? {
        guard let a = here?.latest, let b = there?.latest, abs(a.timeIntervalSince(b)) > 2 else { return nil }
        return a > b ? .send : .bring
    }

    private var isPlaying: Bool {
        #if os(macOS)
        // Another instance's game, or this instance's own: a game window
        // opens Settings (⌘,) too, and its saves screen lists that game.
        SaveSync.isPlayingElsewhere(game.id)
            || (EngineSession.shared.state == .running && EngineSession.shared.currentGame?.id == game.id)
        #else
        EngineSession.shared.state == .running && EngineSession.shared.currentGame?.id == game.id
        #endif
    }

    static var deviceTitle: String {
        #if os(macOS)
        String(localized: "Neste Mac")
        #else
        String(localized: "Neste iPhone")
        #endif
    }

    static var deviceIcon: String {
        #if os(macOS)
        "macbook"
        #else
        "iphone"
        #endif
    }

    private func load() async {
        let folders = SaveSync.GameFolders(game)
        let (local, cloud) = await Task.detached(priority: .userInitiated) {
            (SaveSync.localSide(folders), SaveSync.cloudSide(folders))
        }.value
        here = local
        there = cloud
        noCloud = cloud == nil
    }

    private func run(_ move: Move) async {
        working = move
        defer { working = nil }
        let folders = SaveSync.GameFolders(game)
        do {
            switch move {
            case .send:
                // What iCloud has comes down first, to be kept in Backups:
                // up to 30 s.
                var sent = 0
                var waiting = 0
                for attempt in 0..<15 {
                    let result = try await Task.detached(priority: .userInitiated) { try SaveSync.sendAll(folders) }.value
                    sent = result.sent
                    waiting = result.waiting
                    guard waiting > 0, attempt < 14 else { break }
                    try? await Task.sleep(for: .seconds(2))
                }
                GameLog.shared.note("saves enviados ao iCloud à mão: \(sent), esperando \(waiting)")
                if waiting > 0 {
                    message = String(localized: "\(waiting) arquivo(s) ainda não chegaram do iCloud. Tente de novo daqui a pouco.")
                } else {
                    message = sent == 0 ? String(localized: "O iCloud já tinha estes saves.")
                                        : String(localized: "\(sent) arquivo(s) enviado(s) para o iCloud.")
                }
            case .bring:
                // iCloud may still have to bring files down: up to 30 s.
                var total = 0
                var waiting = 0
                for attempt in 0..<15 {
                    let result = try await Task.detached(priority: .userInitiated) { try SaveSync.bringAll(folders) }.value
                    total += result.brought
                    waiting = result.waiting
                    guard waiting > 0, attempt < 14 else { break }
                    try? await Task.sleep(for: .seconds(2))
                }
                GameLog.shared.note("saves baixados do iCloud à mão: \(total), faltando \(waiting)")
                if waiting > 0 {
                    message = String(localized: "\(waiting) arquivo(s) ainda não chegaram do iCloud. Tente de novo daqui a pouco.")
                } else {
                    message = total == 0 ? String(localized: "Este aparelho já tinha estes saves.")
                                         : String(localized: "\(total) arquivo(s) baixado(s) do iCloud. Os que estavam aqui ficaram em Backups.")
                }
                onChange()
            }
        } catch {
            message = error.localizedDescription
        }
        await load()
    }
}

/// One side, this device or iCloud: when, by whom, how much.
private struct SideCard: View {
    let title: String
    let icon: String
    let side: SaveSync.Side?
    let newer: Bool
    var unavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 4)
                if newer {
                    Text("Mais recente")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.onHighlight)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.highlight))
                }
            }
            Group {
                if unavailable {
                    Text("iCloud indisponível")
                } else if let side {
                    if side.isEmpty {
                        Text("Nenhum save")
                    } else {
                        if let latest = side.latest {
                            Text(latest.formatted(.relative(presentation: .named)))
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.primaryText)
                            Text(latest.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let device = side.device {
                            Text("Por \(device)")
                        }
                        Text(details(side))
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .overlay {
            if newer {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.highlight, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func details(_ side: SaveSync.Side) -> String {
        let size = ByteCountFormatter.string(fromByteCount: side.bytes, countStyle: .file)
        var text = String(localized: "\(side.files) arquivo(s) · \(size)")
        if side.waiting > 0 { text += " · " + String(localized: "\(side.waiting) a baixar") }
        return text
    }
}

/// Every game and where its saves stand (Settings › Saves no iCloud).
struct CloudSavesList: View {
    let games: [GameEntry]
    var onChange: () -> Void = {}

    @State private var sides: [String: (here: SaveSync.Side, there: SaveSync.Side?)] = [:]

    var body: some View {
        List {
            if games.isEmpty {
                Text("Nenhum jogo na estante.").foregroundStyle(Theme.secondaryText)
            }
            ForEach(games) { game in
                NavigationLink {
                    CloudSavesView(game: game, onChange: onChange)
                } label: {
                    row(game)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Saves no iCloud")
        .task { await load() }
    }

    private func row(_ game: GameEntry) -> some View {
        let pair = sides[game.id]
        let automatic = SaveSync.syncsAutomatically(game.id)
        return HStack(spacing: 12) {
            Image(systemName: icon(pair, automatic: automatic))
                .foregroundStyle(automatic ? Theme.activeText : Theme.secondaryText)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.title).foregroundStyle(Theme.primaryText).lineLimit(1)
                Text(summary(pair, automatic: automatic))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }
        }
    }

    private func icon(_ pair: (here: SaveSync.Side, there: SaveSync.Side?)?, automatic: Bool) -> String {
        guard automatic else { return "icloud.slash" }
        guard let pair, let there = pair.there else { return "icloud" }
        if there.isEmpty { return pair.here.isEmpty ? "icloud" : "icloud.and.arrow.up" }
        guard let a = pair.here.latest, let b = there.latest, abs(a.timeIntervalSince(b)) > 2 else {
            return "checkmark.icloud"
        }
        return a > b ? "icloud.and.arrow.up" : "icloud.and.arrow.down"
    }

    private func summary(_ pair: (here: SaveSync.Side, there: SaveSync.Side?)?, automatic: Bool) -> String {
        var parts: [String] = []
        if !automatic { parts.append(String(localized: "Só à mão")) }
        if let pair {
            if let latest = pair.here.latest {
                parts.append(String(localized: "Aqui: \(latest.formatted(.relative(presentation: .named)))"))
            }
            if let there = pair.there, let latest = there.latest {
                parts.append(String(localized: "iCloud: \(latest.formatted(.relative(presentation: .named)))"))
            }
            if pair.here.isEmpty, pair.there?.isEmpty != false { parts.append(String(localized: "Nenhum save")) }
        }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        let all = games.map { SaveSync.GameFolders($0) }
        let result = await Task.detached(priority: .userInitiated) {
            Dictionary(uniqueKeysWithValues: all.map { ($0.id, (here: SaveSync.localSide($0), there: SaveSync.cloudSide($0))) })
        }.value
        sides = result
    }
}
