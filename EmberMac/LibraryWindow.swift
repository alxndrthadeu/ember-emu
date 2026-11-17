import SwiftUI
import UniformTypeIdentifiers

/// The library window: a sidebar (shelves and import) and a grid of
/// covers. Double-click plays, right-click shows the game's options,
/// files dropped anywhere are imported.
struct LibraryWindow: View {
    @Bindable private var library = MacLibrary.shared
    @State private var shelf: Shelf = .all
    @State private var search = ""
    @State private var importing = false
    @State private var dropping = false
    @State private var deleting: GameEntry?
    @State private var selected: GameEntry.ID?
    @State private var info: GameEntry?

    enum Shelf: Hashable {
        case all, recent
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $shelf) {
                Section("Biblioteca") {
                    Label("Todos os jogos", systemImage: "square.grid.2x2").tag(Shelf.all)
                    Label("Recentes", systemImage: "clock").tag(Shelf.recent)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .safeAreaInset(edge: .bottom) {
                if library.syncing {
                    Label("Sincronizando saves…", systemImage: "icloud")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } detail: {
            detail
                .navigationTitle(shelf == .all ? String(localized: "Todos os jogos") : String(localized: "Recentes"))
                .searchable(text: $search, placement: .toolbar, prompt: Text("Buscar"))
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            importing = true
                        } label: {
                            Label("Importar jogo", systemImage: "plus")
                        }
                        .help("Importar um jogo (.zip, .rar, .7z, .exe ou pasta)")
                    }
                }
        }
        .tint(Theme.accent)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .folder, .data],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { library.importItems(urls) }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            receive(providers)
            return true
        }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .alert("Não deu certo", isPresented: Binding(get: { library.lastError != nil },
                                                    set: { if !$0 { library.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.lastError ?? "")
        }
        .alert("Ember", isPresented: Binding(get: { library.notice != nil },
                                            set: { if !$0 { library.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.notice ?? "")
        }
        .sheet(item: $info) { GameInfoView(game: $0) }
        .confirmationDialog("Apagar “\(deleting?.title ?? "")”?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { game in
            Button("Apagar jogo", role: .destructive) { library.delete(game) }
        } message: { _ in
            Text("Os arquivos do jogo saem do Mac. Os saves ficam guardados em Backups.")
        }
    }

    private var shown: [GameEntry] {
        let list = shelf == .all ? library.games : library.recent
        guard !search.isEmpty else { return list }
        return list.filter { $0.title.localizedStandardContains(search) }
    }

    @ViewBuilder
    private var detail: some View {
        if library.games.isEmpty && library.importing.isEmpty {
            empty
        } else {
            ScrollView {
                if shelf == .all, search.isEmpty, let last = library.recent.first {
                    ContinueBanner(game: last) { library.play(last, resume: true) }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 24)], spacing: 28) {
                    ForEach(shown) { game in
                        MacGameCard(game: game, selected: selected == game.id)
                            .onTapGesture(count: 2) { library.play(game) }
                            .simultaneousGesture(TapGesture().onEnded { selected = game.id })
                            .contextMenu {
                                Button("Jogar") { library.play(game) }
                                Button("Continuar de onde parou") { library.play(game, resume: true) }
                                Button("Informações") { info = game }
                                Divider()
                                Button("Mostrar no Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([game.folder])
                                }
                                Divider()
                                Button("Apagar…", role: .destructive) { deleting = game }
                            }
                    }
                }
                .padding(24)
                if !library.importing.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Importando \(library.importing.first ?? "")…")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.bottom, 24)
                }
            }
            .background(Theme.background)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.return) {
                guard let game = selectedGame else { return .ignored }
                library.play(game)
                return .handled
            }
            .onKeyPress(.delete) {
                guard let game = selectedGame else { return .ignored }
                deleting = game
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "i"), phases: .down) { press in
                guard press.modifiers.contains(.command), let game = selectedGame else { return .ignored }
                info = game
                return .handled
            }
        }
    }

    private var selectedGame: GameEntry? {
        library.games.first { $0.id == selected }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            EmberFlame(size: 56)
            Text("Sua estante está vazia")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("Arraste um jogo .zip, .rar, .7z, .exe ou uma pasta para esta janela, ou importe pelo botão +.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: 380)
            HStack {
                Button("Importar jogo…") { importing = true }
                    .buttonStyle(.borderedProminent)
                Button("Experimentar o jogo de exemplo") { library.installDemo() }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private func receive(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in MacLibrary.shared.importItems([url]) }
            }
        }
    }
}

/// A game on the shelf: its cover and title; it lifts under the pointer.
private struct MacGameCard: View {
    let game: GameEntry
    var selected = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MacCover(game: game)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.accent, lineWidth: 3)
                    }
                }
                .shadow(color: .black.opacity(hovering ? 0.25 : 0.1), radius: hovering ? 14 : 6, y: hovering ? 6 : 3)
                .scaleEffect(hovering ? 1.03 : 1)
            Text(game.title)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
            if let last = game.lastPlayed {
                Text("Jogado \(last.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("Clique duas vezes para jogar")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// The last game, big, with a "Continuar" button.
private struct ContinueBanner: View {
    let game: GameEntry
    let onContinue: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            MacCover(game: game)
                .aspectRatio(4 / 3, contentMode: .fit)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("Continuar")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(.uppercase)
                Text(game.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                if let last = game.lastPlayed {
                    Text("Jogado \(last.formatted(.relative(presentation: .named)))")
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
            Button(action: onContinue) {
                Label("Continuar", systemImage: "play.fill")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.highlight)
            .foregroundStyle(Theme.onHighlight)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// The game's cover, or a warm placeholder with its initial.
struct MacCover: View {
    let game: GameEntry

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.surface, Theme.surface2], startPoint: .top, endPoint: .bottom)
            if let url = game.coverURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
            } else {
                Text(String(game.title.prefix(1)).uppercased())
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.secondaryText.opacity(0.8))
            }
        }
    }
}
