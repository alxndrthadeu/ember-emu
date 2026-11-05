import StoreKit
import SwiftUI

struct LibraryView: View {
    @ObservedObject private var session = EngineSession.shared
    @ObservedObject private var library = LibraryStore.shared
    @Environment(\.requestReview) private var requestReview
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
        .alert(library.importNotice?.title ?? "",
               isPresented: Binding(get: { library.importNotice != nil }, set: { if !$0 { library.importNotice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.importNotice?.message ?? "")
        }
        .onReceive(AppRouter.shared.$quickAction.compactMap { $0 }) { handle($0) }
        .onChange(of: session.state) { _, state in
            // A good moment to ask for a rating: a long session just
            // ended well (see ReviewPrompt).
            guard state == .finished, ReviewPrompt.isGoodMoment else { return }
            ReviewPrompt.markAsked()
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                requestReview()
            }
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
                ContinueCard(game: recent, resumes: StateStore.autoState(for: recent.id) != nil)
                    .onTapGesture { open(recent, resume: true) }
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
                .emberGlassProminentButton()
                .tint(Theme.accent)
                .controlSize(.large)
                .padding(.top, 10)
            if LibraryStore.demoFolder != nil {
                Button("Experimentar o jogo de exemplo") { library.installDemo() }
                    .font(.subheadline.weight(.semibold))
                    .tint(Theme.accent)
                    .padding(.top, 2)
            }
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

    /// The app icon's quick actions.
    private func handle(_ action: QuickAction) {
        AppRouter.shared.quickAction = nil
        switch action {
        case .continueLast:
            AppRouter.shared.tab = .library
            if let recent = library.recent { open(recent, resume: true) }
        case .importGame:
            AppRouter.shared.tab = .importGames
        case .wifi:
            AppRouter.shared.tab = .importGames
            WifiTransfer.shared.start()
        }
    }

    private func showOptions(_ game: GameEntry) {
        Haptics.tap()
        optionsFor = game
    }

    /// One game per app launch: after a game ended, the next one
    /// needs the app reopened (see CLAUDE.md, "Limite atual").
    /// `resume`: start from the automatic save state when there is one.
    private func open(_ game: GameEntry, resume: Bool = false) {
        switch session.state {
        case .idle:
            let slot = resume && StateStore.autoState(for: game.id) != nil ? StateStore.autoSlot : nil
            session.launch(game, resumeSlot: slot)
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
    ///   EMBER_KEYS="3:enter,1:down,2:save:t1,2:load:t1,1:snap"  drives the
    ///   game: wait N seconds, then press a key / save or load a state
    ///   EMBER_RESUME=1            starts from the auto state
    ///   EMBER_IMPORT_SAVES=<path>[:<path>…]  imports saves into the first game
    ///   EMBER_EXPORT_SAVES=1      exports the first game's saves (logs the .zip)
    ///   EMBER_WIFI=1              turns on the Wi-Fi transfer (logs the address)
    ///   EMBER_INSTALL_DEMO=1      copies the bundled demo game into the library
    ///   EMBER_SHARE_SAVES=<id>    builds that game's .embersave (logs the path)
    ///   EMBER_QUICK=continue|import|wifi  acts as an app icon quick action
    ///   EMBER_TV=1                starts "Jogar na TV" 8 s after the game opens
    ///   EMBER_MAKE_BACKUP=<id>    writes a backup with that whole game (logs the path)
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
        if let id = environment["EMBER_SHARE_SAVES"], let game = library.games.first(where: { $0.id == id }) {
            print("[ember-share]", Result { try SaveShare.package(game) })
        }
        if let id = environment["EMBER_MAKE_BACKUP"] {
            var options = EmberBackup.Options()
            options.games = [id]
            print("[ember-backup]", Result { try EmberBackup.make(options, library: library.games) })
        }
        if let quick = environment["EMBER_QUICK"] {
            let map: [String: QuickAction] = ["continue": .continueLast, "import": .importGame, "wifi": .wifi]
            AppRouter.shared.quickAction = map[quick]
        }
        if environment["EMBER_INSTALL_DEMO"] != nil {
            library.installDemo()
        }
        if environment["EMBER_WIFI"] != nil {
            WifiTransfer.shared.start()
            Task {
                try? await Task.sleep(for: .seconds(1))
                print("[ember-wifi]", WifiTransfer.shared.address ?? "no address")
            }
        }
        switch environment["EMBER_SHOW"] {
        case "history": showingHistory = true
        case "controls": showingControls = true
        case "options": optionsFor = library.games.first
        case "import", "computer", "rtp": AppRouter.shared.tab = .importGames
        case "settings": AppRouter.shared.tab = .settings
        default: break
        }
        guard let id = environment["EMBER_AUTOLAUNCH"],
              let game = library.games.first(where: { $0.id == id || id == "first" })
        else { return }
        let resume = environment["EMBER_RESUME"] != nil ? StateStore.autoSlot : nil
        session.launch(game, resumeSlot: resume)
        if environment["EMBER_TV"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(8))
                TVStream.shared.start()
                try? await Task.sleep(for: .seconds(1))
                print("[ember-tv]", TVStream.shared.address ?? "no address", TVStream.shared.isOn)
            }
        }
        if let script = environment["EMBER_KEYS"] {
            Task { await runKeyScript(script) }
        }
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

#if DEBUG
/// Development aid behind EMBER_KEYS: steps of "seconds:action".
@MainActor
private func runKeyScript(_ script: String) async {
    let keys: [String: GameKey] = ["enter": .confirm, "esc": .back, "shift": .start, "up": .up,
                                   "down": .down, "left": .left, "right": .right]
    for step in script.split(separator: ",") {
        let parts = step.split(separator: ":").map(String.init)
        guard let seconds = Double(parts.first ?? "") , parts.count >= 2 else { continue }
        try? await Task.sleep(for: .seconds(seconds))
        switch parts[1] {
        case "save", "load":
            let slot = parts.count > 2 ? parts[2] : StateStore.autoSlot
            let outcome = await EngineSession.shared.requestState(parts[1], slot: slot)
            print("[ember-keys] \(parts[1]) \(slot): \(outcome)")
        default:
            if let key = keys[parts[1]] {
                key.press()
                try? await Task.sleep(for: .milliseconds(90))
                key.release()
            } else if parts[1].count == 1, let character = parts[1].first {
                KeyTapper.type(character)
            }
            print("[ember-keys] \(parts[1])")
        }
    }
}
#endif

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
            .emberGlassProminentButton()
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
    /// An automatic save state is waiting: the game opens right there.
    var resumes = false

    var body: some View {
        CoverFrame(game: game, ratio: 16 / 10, initialSize: 64)
            .overlay(alignment: .bottom) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if resumes {
                            Text("Volta de onde você parou")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.8))
                        } else if let lastPlayed = game.lastPlayed {
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
                        .emberGlass(.regular.tint(Theme.highlight), in: Capsule())
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
            .emberGlass(.regular, in: Capsule())
            .padding(.bottom, 8)
    }
}
