import SwiftUI

struct LibraryView: View {
    @ObservedObject private var session = EngineSession.shared
    @ObservedObject private var library = LibraryStore.shared
    @State private var optionsFor: GameEntry?
    @State private var showingHistory = false
    @State private var showingControls = false
    /// A game tapped after another one ended: the app must reopen.
    @State private var reopenFor: GameEntry?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if library.games.isEmpty && library.importing.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Biblioteca")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingControls = true } label: {
                        Image(systemName: "gamecontroller")
                    }
                    .accessibilityLabel("Controles")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Histórico")
                }
            }
            .safeAreaInset(edge: .bottom) { statusBanner }
        }
        .alert("Não deu certo",
               isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.lastError ?? "")
        }
        .sheet(item: $optionsFor) { game in
            GameOptionsSheet(game: game) { open(game) }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView { open($0) }
        }
        .sheet(isPresented: $showingControls) {
            ControlsGuideView()
        }
        .sheet(item: $reopenFor) { game in
            ReopenSheet(title: game.title)
                .presentationDetents([.height(320)])
        }
        .onAppear(perform: developmentHooks)
    }

    private var grid: some View {
        ScrollView {
            if let recent = library.recent {
                ContinueCard(game: recent)
                    .onTapGesture { open(recent) }
                    .onLongPressGesture { showOptions(recent) }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                Text("Todos os jogos")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(library.games) { game in
                    GameCard(game: game)
                        .onTapGesture { open(game) }
                        .onLongPressGesture { showOptions(game) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: "Opções") { showOptions(game) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            EmberFlame(size: 52)
                .padding(.bottom, 8)
            Text("Sua estante está vazia")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("Importe um jogo .zip ou uma pasta para começar.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button("Importar jogo") { AppRouter.shared.tab = .importGames }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .padding(.top, 10)
        }
        .padding(32)
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let name = library.importing.first {
            Banner {
                ProgressView()
                Text(library.importing.count > 1
                     ? "Importando \(library.importing.count) jogos…"
                     : "Importando \(name)…")
            }
        } else if case .failed(let message) = session.state {
            Banner {
                Image(systemName: "exclamationmark.triangle")
                Text(message)
            }
        }
    }

    private func showOptions(_ game: GameEntry) {
        Haptics.tap()
        optionsFor = game
    }

    /// One game per app launch: after a game ended, the next one
    /// needs the app reopened (see CLAUDE.md, "Limite atual").
    private func open(_ game: GameEntry) {
        switch session.state {
        case .idle:
            session.launch(game)
        case .finished:
            reopenFor = game
        case .preparing, .running, .failed:
            break
        }
    }

    /// Development aids, so the simulator can be driven from the
    /// command line:
    ///   EMBER_IMPORT=<path>       imports a .zip or folder at launch
    ///   EMBER_AUTOLAUNCH=<id>     starts that game ("first" = any)
    ///   EMBER_AUTOQUIT=<seconds>  then quits it, as the menu's Sair does
    ///   EMBER_AUTOREOPEN=1        then taps the game again
    ///   EMBER_AUTOMENU=<seconds>  opens the in-game menu (ControlsOverlay)
    ///   EMBER_SHOW=history|controls|options|import  opens that screen
    ///   EMBER_IMPORT_SAVES=<path>[:<path>…]  imports saves into the first game
    ///   EMBER_EXPORT_SAVES=1      exports the first game's saves (logs the .zip)
    private func developmentHooks() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let paths = environment["EMBER_IMPORT"] {
            library.importItems(paths.split(separator: ":").map { URL(fileURLWithPath: String($0)) })
        }
        if let game = library.games.first {
            if let paths = environment["EMBER_IMPORT_SAVES"] {
                let urls = paths.split(separator: ":").map { URL(fileURLWithPath: String($0)) }
                print("[ember-saves] import:", Result { try SaveManager.importSaves(from: urls, into: game) })
            }
            if environment["EMBER_EXPORT_SAVES"] != nil {
                print("[ember-saves] export:", Result { try SaveManager.export(game) })
            }
        }
        switch environment["EMBER_SHOW"] {
        case "history": showingHistory = true
        case "controls": showingControls = true
        case "options": optionsFor = library.games.first
        case "import": AppRouter.shared.tab = .importGames
        case "settings": AppRouter.shared.tab = .settings
        default: break
        }
        guard let id = environment["EMBER_AUTOLAUNCH"],
              let game = library.games.first(where: { $0.id == id || id == "first" })
        else { return }
        session.launch(game)
        if let seconds = environment["EMBER_AUTOQUIT"].flatMap(Double.init) {
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                session.quit()
                if environment["EMBER_AUTOREOPEN"] != nil {
                    try? await Task.sleep(for: .seconds(2))
                    open(game)
                }
            }
        }
        #endif
    }
}

/// Explains, in the app's voice, how to open another game.
private struct ReopenSheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            EmberFlame(size: 40)
                .padding(.top, 12)
            Text("Feche o Ember para abrir \(title)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
            Text("O Ember abre um jogo por vez. Deslize de baixo para cima, feche o Ember no seletor de apps e abra de novo. Seus saves estão guardados.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button { dismiss() } label: {
                Text("Entendi").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.accent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}

/// The last game played, big, with "Continuar" in âmbar.
private struct ContinueCard: View {
    let game: GameEntry

    var body: some View {
        CoverFrame(game: game, ratio: 16 / 10, initialSize: 64)
            .overlay(alignment: .bottom) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let lastPlayed = game.lastPlayed {
                            Text("Jogado \(lastPlayed.formatted(.relative(presentation: .named)))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    Spacer()
                    Label("Continuar", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.onHighlight)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.tint(Theme.highlight), in: Capsule())
                }
                .padding(14)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom))
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Theme.cardRadius,
                                                  bottomTrailingRadius: Theme.cardRadius,
                                                  style: .continuous))
            }
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Continuar \(game.title)")
    }
}

private struct GameCard: View {
    let game: GameEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverFrame(game: game)
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            Text(game.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
        }
        .contentShape(Rectangle())
    }
}

private struct Banner<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: Capsule())
            .padding(.bottom, 8)
    }
}
