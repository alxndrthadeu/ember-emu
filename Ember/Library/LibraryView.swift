import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject private var session = EngineSession.shared
    @ObservedObject private var library = LibraryStore.shared
    @State private var showingImporter = false
    @State private var pendingDelete: GameEntry?
    /// A game tapped after another one ended: the app must reopen.
    @State private var reopenFor: GameEntry?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if library.games.isEmpty && library.importing.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    grid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { statusBanner }
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.zip, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                library.importItems(urls)
            }
        }
        .confirmationDialog(
            "Apagar “\(pendingDelete?.title ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Apagar jogo", role: .destructive) {
                if let game = pendingDelete { library.delete(game) }
            }
        } message: {
            Text("Os saves continuam guardados. Se importar o jogo de novo, eles voltam.")
        }
        .alert("Não deu certo",
               isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.lastError ?? "")
        }
        .sheet(item: $reopenFor) { game in
            ReopenSheet(title: game.title)
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        }
        .onAppear(perform: autoLaunchForDevelopment)
    }

    /// The library's own header, as in Manic EMU: the title in
    /// Pixelify on the left, actions on the right.
    private var header: some View {
        HStack(alignment: .center) {
            Text("Biblioteca")
                .pixelFont(34)
                .foregroundStyle(Theme.primaryText)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { showingImporter = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.surface2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Importar jogo")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(library.games) { game in
                    Button { open(game) } label: {
                        GameCard(game: game)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { pendingDelete = game } label: {
                            Label("Apagar", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            PixelFlame(cell: 9)
                .padding(.bottom, 10)
            Text("Sua estante está vazia")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("Importe um jogo .zip ou uma pasta para começar.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button { showingImporter = true } label: {
                Text("Importar jogo")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
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
    private func autoLaunchForDevelopment() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["EMBER_IMPORT"] {
            library.importItems([URL(fileURLWithPath: path)])
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
        VStack(spacing: 14) {
            PixelFlame(cell: 6)
                .padding(.top, 8)
            Text("Feche o Ember para abrir \(title)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
            Text("O Ember abre um jogo por vez. Deslize de baixo para cima, feche o Ember no seletor de apps e abra de novo. Seus saves estão guardados.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button { dismiss() } label: {
                Text("Entendi")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Theme.accent))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.ignoresSafeArea())
    }
}

private struct GameCard: View {
    let game: GameEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .stroke(Theme.surface2, lineWidth: 1))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Text(String(game.title.prefix(1)).uppercased())
                        .pixelFont(48)
                        .foregroundStyle(Theme.secondaryText)
                }
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Capsule().fill(Theme.surface2))
            .padding(.bottom, 8)
    }
}
