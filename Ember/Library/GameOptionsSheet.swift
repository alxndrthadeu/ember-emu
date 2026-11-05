import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The sheet a long press on a game opens: play, rename, cover, saves,
/// delete.
struct GameOptionsSheet: View {
    let game: GameEntry
    let onPlay: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = LibraryStore.shared
    @State private var saves: [SaveManager.SaveFile] = []
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var photo: PhotosPickerItem?
    @State private var exportFile: ExportFile?
    @State private var importingSaves = false
    @State private var confirmingDelete = false
    @State private var toast: String?
    @State private var working = false
    @State private var showingLogs = false

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    /// The entry as the library holds it now (title or cover may have
    /// changed while the sheet is open).
    private var current: GameEntry {
        library.games.first { $0.id == game.id } ?? game
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                EmberGlassContainer(spacing: 12) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        OptionTile(icon: "play.fill", title: String(localized: "Jogar"), highlighted: true) {
                            dismiss()
                            onPlay()
                        }
                        OptionTile(icon: "pencil", title: String(localized: "Renomear")) {
                            newTitle = current.title
                            renaming = true
                        }
                        PhotosPicker(selection: $photo, matching: .images) {
                            OptionTileLabel(icon: "photo", title: String(localized: "Capa"))
                        }
                        .buttonStyle(.plain)
                        .emberGlass(.regular.interactive(), in: tileShape)
                        if GameCovers.hasCustomCover(current.id) {
                            OptionTile(icon: "arrow.uturn.backward", title: String(localized: "Capa automática")) {
                                library.removeCustomCover(for: current)
                                show(String(localized: "Capa automática de volta"))
                            }
                        }
                        Menu {
                            Picker("Ruby", selection: Binding(
                                get: { RubyChoice.saved(for: current.id) },
                                set: { choice in
                                    RubyChoice.set(choice, for: current.id)
                                    library.reload()
                                    show(String(localized: "Vale na próxima vez que o jogo abrir"))
                                })) {
                                Text("Automático (\(RubyChoice.label(for: current.detectedRubyVersion)))")
                                    .tag(RubyChoice?.none)
                                ForEach(RubyChoice.allCases) { choice in
                                    Text("Ruby \(choice.label)").tag(RubyChoice?.some(choice))
                                }
                            }
                        } label: {
                            OptionTileLabel(icon: "chevron.left.forwardslash.chevron.right",
                                            title: String(localized: "Ruby \(RubyChoice.label(for: current.rubyVersion))"))
                        }
                        .buttonStyle(.plain)
                        .emberGlass(.regular.interactive(), in: tileShape)
                        OptionTile(icon: InGameKeyboard.isOn(for: current.id) ? "keyboard.fill" : "keyboard",
                                   title: InGameKeyboard.isOn(for: current.id) ? String(localized: "Teclado do jogo: ligado") : String(localized: "Teclado do jogo"),
                                   highlighted: false) {
                            let on = !InGameKeyboard.isOn(for: current.id)
                            InGameKeyboard.set(on, for: current.id)
                            library.reload()
                            show(on ? String(localized: "O jogo vai usar o próprio teclado na próxima vez que abrir")
                                    : String(localized: "O Ember volta a usar o teclado do iPhone"))
                        }
                        Menu {
                            Picker("Controles", selection: Binding(
                                get: { ProfileStore.shared.isAutomatic(current) ? nil : ProfileStore.shared.profile(for: current).id },
                                set: { id in
                                    ProfileStore.shared.assign(ProfileStore.shared.all.first { $0.id == id }, to: current)
                                    library.reload()
                                    show(String(localized: "Vale na próxima vez que o jogo abrir"))
                                })) {
                                Text("Automático (\(ProfileStore.shared.automaticProfile(for: current).name))")
                                    .tag(String?.none)
                                ForEach(ProfileStore.shared.all) { profile in
                                    Text(profile.name).tag(String?.some(profile.id))
                                }
                            }
                        } label: {
                            OptionTileLabel(icon: "gamecontroller",
                                            title: String(localized: "Controles: \(ProfileStore.shared.profile(for: current).name)"))
                        }
                        .buttonStyle(.plain)
                        .emberGlass(.regular.interactive(), in: tileShape)
                        OptionTile(icon: "square.and.arrow.up", title: String(localized: "Exportar saves")) {
                            exportSaves()
                        }
                        OptionTile(icon: "square.and.arrow.down", title: String(localized: "Importar saves")) {
                            importingSaves = true
                        }
                        OptionTile(icon: "doc.text.magnifyingglass", title: String(localized: "Registros")) {
                            showingLogs = true
                        }
                        OptionTile(icon: "trash", title: String(localized: "Apagar"), destructive: true) {
                            confirmingDelete = true
                        }
                    }
                }
                savesSection
            }
            .padding(20)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.onHighlight)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .emberGlass(.regular.tint(Theme.highlight), in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .onAppear(perform: refreshSaves)
        .onChange(of: photo) { loadPhoto() }
        .alert("Renomear", isPresented: $renaming) {
            TextField(current.originalTitle, text: $newTitle)
            Button("Cancelar", role: .cancel) {}
            Button("Salvar") { library.rename(current, to: newTitle) }
        } message: {
            Text("Muda só o nome na biblioteca. A pasta e os saves continuam iguais.")
        }
        .fileImporter(isPresented: $importingSaves,
                      allowedContentTypes: [.zip, .folder, .data],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            importSaves(urls)
        }
        .sheet(isPresented: $showingLogs) {
            LogsView(game: current)
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(url: file.url)
        }
        .confirmationDialog("Apagar \(current.title)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Apagar jogo", role: .destructive) {
                dismiss()
                library.delete(current)
            }
        } message: {
            Text("Os arquivos do jogo saem do iPhone. Os saves ficam guardados no Ember: importe o jogo de novo e eles voltam.")
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 14) {
            CoverFrame(game: current, radius: 14, initialSize: 28)
                .frame(width: 112)
            VStack(alignment: .leading, spacing: 4) {
                Text(current.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                if let lastPlayed = current.lastPlayed {
                    Text("Jogado \(lastPlayed.formatted(.relative(presentation: .named)))")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                let total = PlayHistory.totalTime(current.id)
                if total >= 60 {
                    Text("\(durationText(total)) no total")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var savesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saves")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                if working { ProgressView() }
            }
            if saves.isEmpty {
                Text("Nenhum save ainda. Para continuar de onde parou em outro aparelho, use Importar saves com os arquivos do jogo (.rxdata, .rvdata ou .rvdata2) ou um .zip deles.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(saves) { save in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundStyle(Theme.secondaryText)
                            Text(save.id)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.primaryText)
                                .lineLimit(1)
                            Spacer()
                            Text(save.modified.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.vertical, 8)
                        if save.id != saves.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .emberGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            // verbatim: a plain Text reads the string as Markdown, which
            // eats the backslash of %APPDATA%\.
            Text(verbatim: String(localized: "No PC, os saves ficam na pasta do jogo (Save1.rxdata, Save01.rvdata2) ou, nos fangames de Pokémon, em %APPDATA%\\\(current.originalTitle) (Game.rxdata). O Ember usa os mesmos arquivos."))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: Actions

    private func refreshSaves() {
        saves = SaveManager.saves(for: current).sorted { $0.modified > $1.modified }
    }

    private func loadPhoto() {
        guard let photo else { return }
        Task {
            if let data = try? await photo.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                library.setCover(image, for: current)
                show(String(localized: "Capa atualizada"))
            }
            self.photo = nil
        }
    }

    private func exportSaves() {
        let game = current
        working = true
        Task.detached(priority: .userInitiated) {
            let result = Result { try SaveManager.export(game) }
            await MainActor.run {
                working = false
                switch result {
                case .success(let url): exportFile = ExportFile(url: url)
                case .failure(let error): show(error.localizedDescription)
                }
            }
        }
    }

    private func importSaves(_ urls: [URL]) {
        let game = current
        working = true
        Task.detached(priority: .userInitiated) {
            let result = Result { try SaveManager.importSaves(from: urls, into: game) }
            await MainActor.run {
                working = false
                switch result {
                case .success(let count):
                    show(count == 1 ? String(localized: "1 save importado") : String(localized: "\(count) saves importados"))
                case .failure(let error):
                    show(error.localizedDescription)
                }
                refreshSaves()
            }
        }
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { if toast == message { toast = nil } }
        }
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }
}

private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct OptionTile: View {
    let icon: String
    let title: String
    var highlighted = false
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            OptionTileLabel(icon: icon, title: title, highlighted: highlighted, destructive: destructive)
        }
        .buttonStyle(.plain)
        .emberGlass(highlighted ? .regular.tint(Theme.highlight).interactive() : .regular.interactive(),
                     in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct OptionTileLabel: View {
    let icon: String
    let title: String
    var highlighted = false
    var destructive = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .frame(height: 24)
            Text(title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .foregroundStyle(highlighted ? Theme.onHighlight : destructive ? Theme.accent : Theme.primaryText)
        .frame(maxWidth: .infinity, minHeight: 84)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// The system share sheet for one file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
