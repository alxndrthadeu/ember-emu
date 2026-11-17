import StoreKit
import SwiftUI

struct LibraryView: View {
    @Bindable var session = EngineSession.shared
    @Bindable var library = LibraryStore.shared
    @Environment(\.requestReview) private var requestReview
    @State var optionsFor: GameEntry?
    @State var showingHistory = false
    @State var showingControls = false
    @State var showingSendToMac = false
    @State private var incomingFor: (game: GameEntry, resume: Bool)?
    @State private var waitingForSave = false
    /// A game tapped after another one ended: the app must reopen.
    @State private var reopenFor: GameEntry?
    @State private var removingArchived: ArchivedGame?

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if library.games.isEmpty && library.archived.isEmpty && library.importing.isEmpty {
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
                    .accessibilityLabel("Guia de controles")
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
        .sheet(isPresented: $showingSendToMac) { SendToMacView() }
        .alert("Tem um save mais novo chegando", isPresented: Binding(
            get: { incomingFor != nil }, set: { if !$0 { incomingFor = nil } })) {
            Button("Esperar o save") {
                guard let pending = incomingFor else { return }
                waitingForSave = true
                Task {
                    let arrived = await SyncStatus.waitForIncoming(pending.game)
                    waitingForSave = false
                    library.reload()
                    if !arrived { SyncStatus.shared.show(String(localized: "O save ainda não chegou. Abrindo com o que está aqui.")) }
                    let game = library.games.first { $0.id == pending.game.id } ?? pending.game
                    open(game, resume: pending.resume, checked: true)
                }
            }
            Button("Jogar mesmo assim", role: .destructive) {
                guard let pending = incomingFor else { return }
                open(pending.game, resume: pending.resume, checked: true)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Este jogo foi salvo em outro aparelho e o save ainda está vindo do iCloud. Se jogar agora, você começa do save antigo.")
        }
        .overlay(alignment: .top) {
            if waitingForSave {
                SyncToast(text: String(localized: "Esperando o save chegar…"), busy: true)
            } else if let toast = SyncStatus.shared.toast {
                SyncToast(text: toast, busy: false)
            }
        }
        .animation(.spring(response: 0.35), value: SyncStatus.shared.toast)
        .animation(.spring(response: 0.35), value: waitingForSave)
        .onAppear {
            // Only once the player has used a Mac link: browsing asks for
            // the local network permission.
            if GameSender.usedBefore { GameSender.shared.browse() }
        }
        .alert("Não deu certo",
               isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.lastError ?? "")
        }
        .confirmationDialog(
            "Versão nova de “\(library.updateOffer?.existing.title ?? "")”?",
            isPresented: Binding(get: { library.updateOffer != nil },
                                 set: { if !$0, let offer = library.updateOffer { library.keepBoth(offer) } }),
            titleVisibility: .visible,
            presenting: library.updateOffer
        ) { offer in
            Button("Atualizar o jogo") { library.applyUpdate(offer) }
            Button("Manter os dois") { library.keepBoth(offer) }
        } message: { _ in
            Text("Ao atualizar, os arquivos novos substituem os antigos. Saves, estados, capa e controles continuam, e os saves ficam guardados também em Backups.")
        }
        .alert(library.importNotice?.title ?? "",
               isPresented: Binding(get: { library.importNotice != nil }, set: { if !$0 { library.importNotice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.importNotice?.message ?? "")
        }
        .onChange(of: AppRouter.shared.quickAction, initial: true) { _, action in
            if let action { handle(action) }
        }
        .onChange(of: AppRouter.shared.gameToOpen, initial: true) { _, id in
            guard let id else { return }
            AppRouter.shared.gameToOpen = nil
            AppRouter.shared.tab = .library
            if let game = library.games.first(where: { $0.id == id }) { open(game) }
        }
        .alert("Ruby trocado",
               isPresented: Binding(get: { session.rubyChangedAfterError != nil && session.state != .running },
                                    set: { if !$0 { session.rubyChangedAfterError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Na próxima vez, o jogo abre com o Ruby \(session.rubyChangedAfterError ?? ""). Para abrir agora, feche o Ember pelo seletor de apps e abra de novo.")
        }
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
        .sheet(item: $library.chooseController) { game in
            ControllerChoiceView(game: game)
                .presentationDetents([.large])
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
                .presentationDetents([.height(320), .large])
        }
        .onAppear(perform: developmentHooks)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Cards grow in, or only fade with Reduce Motion.
    private var cardTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity)
    }

    /// A Mac with Ember open nearby: offer to send games there.
    @ViewBuilder
    private var macNearby: some View {
        if let mac = GameSender.shared.macs.first, !library.games.isEmpty {
            Button {
                AppRouter.shared.tab = .mac
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "macbook")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: mac.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text("Está por perto com o Ember aberto")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Text("Abrir")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    private var grid: some View {
        ScrollView {
            macNearby
            if let recent = library.recent {
                ContinueCard(game: recent, resumes: StateStore.autoState(for: recent.id) != nil)
                    .cardPress(onTap: { open(recent, resume: true) }, onLongPress: { showOptions(recent) })
                    .accessibilityAction(named: "Opções") { showOptions(recent) }
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
                    GameCard(game: game, status: library.archiveStatus[game.id])
                        .transition(cardTransition)
                        .cardPress(onTap: { if library.archiveStatus[game.id] == nil { open(game) } },
                                   onLongPress: { showOptions(game) })
                        .accessibilityAction(named: "Opções") { showOptions(game) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)

            if !library.archived.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "icloud")
                    Text("No iCloud")
                }
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                Text("Toque para baixar de volta. Saves e capa ficaram no iPhone.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(library.archived) { record in
                        ArchivedCard(record: record, status: library.archiveStatus[record.id],
                                     progress: library.archiveProgress[record.id])
                            .transition(cardTransition)
                            .cardPress(onTap: { library.unarchive(record) },
                                       onLongPress: { removingArchived = record })
                            .accessibilityHint("Baixa o jogo de volta do iCloud")
                            .accessibilityAction(named: "Apagar do iCloud") { removingArchived = record }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .confirmationDialog("Apagar do iCloud?", isPresented: Binding(get: { removingArchived != nil },
                                                                        set: { if !$0 { removingArchived = nil } }),
                            titleVisibility: .visible) {
            Button("Apagar do iCloud", role: .destructive) {
                if let record = removingArchived { library.deleteArchived(record) }
            }
        } message: {
            Text("O jogo sai do iCloud de vez. Os saves que ficaram no iPhone continuam.")
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
                // A choice between two literals is a String, which SwiftUI
                // does not translate: each branch is its own Text.
                if library.importing.count > 1 {
                    Text("Importando \(library.importing.count) jogos…")
                } else {
                    Text("Importando \(name)…")
                }
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
    func open(_ game: GameEntry, resume: Bool = false, checked: Bool = false) {
        switch session.state {
        case .idle:
            // A newer save from the Mac still coming down: ask before
            // starting from the old one.
            if !checked, SaveSync.isEnabled {
                Task {
                    let folders = SaveSync.GameFolders(game)
                    let incoming = await Task.detached(priority: .userInitiated) { SaveSync.hasIncoming(folders) }.value
                    if incoming { incomingFor = (game, resume) } else { open(game, resume: resume, checked: true) }
                }
                return
            }
            let slot = resume && StateStore.autoState(for: game.id) != nil ? StateStore.autoSlot : nil
            session.launch(game, resumeSlot: slot)
        case .finished:
            reopenFor = game
        case .preparing, .running, .failed:
            break
        }
    }
}
