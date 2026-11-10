import SwiftUI
import UIKit

/// Every save of one game, as cards with a picture: the game's own
/// saves (the map where it was saved) and Ember's save states.
struct SavesView: View {
    let game: GameEntry

    @Environment(\.dismiss) private var dismiss
    @State private var saves: [SaveManager.SaveFile] = []
    @State private var states: [StateStore.SaveState] = []
    @State private var sharing: SharedFile?
    @State private var importing = false
    @State private var deleting: SaveManager.SaveFile?
    @State private var working = false
    @State private var message: String?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if saves.isEmpty && states.isEmpty {
                        empty
                    }
                    if !saves.isEmpty {
                        section(String(localized: "Saves do jogo"),
                                footer: String(localized: "Os mesmos arquivos do PC. A imagem é o mapa de quando o jogo salvou; saves de antes desta versão ou importados mostram a capa.")) {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(saves) { save in
                                    SaveCard(game: game,
                                             image: SaveThumbnails.image(for: save, gameID: game.id),
                                             title: SaveThumbnails.displayName(save),
                                             detail: save.modified.formatted(.relative(presentation: .named)))
                                    .contextMenu {
                                        Button {
                                            sharing = SharedFile(url: save.url)
                                        } label: {
                                            Label("Compartilhar arquivo", systemImage: "square.and.arrow.up")
                                        }
                                        Button(role: .destructive) {
                                            deleting = save
                                        } label: {
                                            Label("Apagar", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if !states.isEmpty {
                        section(String(localized: "Estados do Ember"),
                                footer: String(localized: "Para carregar um estado, abra o jogo e use Estados no menu.")) {
                            LazyVGrid(columns: columns, spacing: 14) {
                                ForEach(states) { state in
                                    SaveCard(game: game,
                                             image: state.thumbnail.flatMap { UIImage(contentsOfFile: $0.path) },
                                             title: state.isAuto ? String(localized: "Automático") : String(localized: "Estado salvo"),
                                             detail: state.date.formatted(.relative(presentation: .named)),
                                             badge: state.isAuto ? "clock.arrow.circlepath" : nil)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            StateStore.delete(state, gameID: game.id)
                                            reload()
                                        } label: {
                                            Label("Apagar", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Saves")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Fechar")
                }
                ToolbarItem(placement: .primaryAction) {
                    if working {
                        ProgressView()
                    } else {
                        Menu {
                            Button { importing = true } label: {
                                Label("Importar saves", systemImage: "square.and.arrow.down")
                            }
                            Button { run { try SaveManager.export(game) } } label: {
                                Label("Exportar todos (.zip)", systemImage: "square.and.arrow.up")
                            }
                            .disabled(saves.isEmpty)
                            Button { run { try SaveShare.package(game) } } label: {
                                Label("Enviar para outro iPhone", systemImage: "iphone.radiowaves.left.and.right")
                            }
                            .disabled(saves.isEmpty)
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Mais")
                    }
                }
            }
            .onAppear(perform: reload)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .folder, .data],
                          allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result, !urls.isEmpty else { return }
                importSaves(urls)
            }
            .sheet(item: $sharing) { file in
                ShareSheet(url: file.url)
            }
            .confirmationDialog(deleting.map { String(localized: "Apagar \(SaveThumbnails.displayName($0))?") } ?? "",
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Apagar", role: .destructive) {
                    if let save = deleting { delete(save) }
                }
            } message: {
                Text("O arquivo sai do jogo e fica guardado em Backups, no app Arquivos.")
            }
            .alert("Saves", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.secondaryText)
            Text("Nenhum save ainda")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text("Salve dentro do jogo e ele aparece aqui. Para continuar de outro aparelho, importe os arquivos (.rxdata, .rvdata ou .rvdata2) ou um .zip deles.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button {
                importing = true
            } label: {
                Label("Importar saves", systemImage: "square.and.arrow.down")
            }
            .emberGlassProminentButton()
            .tint(Theme.accent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func section<Content: View>(_ title: String, footer: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
                .padding(.leading, 4)
            content()
            Text(footer)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 4)
        }
    }

    private func reload() {
        saves = SaveManager.saves(for: game).sorted { $0.modified > $1.modified }
        states = StateStore.states(for: game.id)
    }

    private func delete(_ save: SaveManager.SaveFile) {
        do {
            try SaveManager.delete(save, of: game)
        } catch {
            message = error.localizedDescription
        }
        deleting = nil
        reload()
    }

    /// Makes a file off the main thread, then shares it.
    private func run(_ make: @escaping @Sendable () throws -> URL) {
        working = true
        Task.detached(priority: .userInitiated) {
            let result = Result { try make() }
            await MainActor.run {
                working = false
                switch result {
                case .success(let url): sharing = SharedFile(url: url)
                case .failure(let error): message = error.localizedDescription
                }
            }
        }
    }

    private func importSaves(_ urls: [URL]) {
        let game = game
        working = true
        Task.detached(priority: .userInitiated) {
            let result = Result { try SaveManager.importSaves(from: urls, into: game) }
            await MainActor.run {
                working = false
                switch result {
                case .success(let count):
                    message = count == 1 ? String(localized: "1 save importado") : String(localized: "\(count) saves importados")
                case .failure(let error):
                    message = error.localizedDescription
                }
                reload()
            }
        }
    }
}

private struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// One save: its picture (or the game's cover, dimmed), name and date.
struct SaveCard: View {
    let game: GameEntry
    let image: UIImage?
    let title: String
    let detail: String
    var badge: String?
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.black
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                    } else {
                        CoverFrame(game: game, radius: 0, initialSize: compact ? 18 : 28)
                            .opacity(0.45)
                            .overlay {
                                Image(systemName: "doc.fill")
                                    .font(.system(size: compact ? 18 : 24))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Image(systemName: badge)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.onHighlight)
                            .padding(5)
                            .background(Theme.highlight, in: Circle())
                            .padding(6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font((compact ? Font.footnote : .subheadline).weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
    }
}
