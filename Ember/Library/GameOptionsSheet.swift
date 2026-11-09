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
    @State private var showingSaves = false
    @State private var choosingController = false
    @State private var confirmingDelete = false
    @State private var confirmingArchive = false
    @State private var toast: String?
    @State private var working = false
    @State private var showingLogs = false

    /// The entry as the library holds it now (title or cover may have
    /// changed while the sheet is open).
    private var current: GameEntry {
        library.games.first { $0.id == game.id } ?? game
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                // The one thing most people came for.
                Button {
                    dismiss()
                    onPlay()
                } label: {
                    Label("Jogar", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .emberGlassProminentButton()
                .tint(Theme.accent)
                .controlSize(.large)

                quickActions

                group(String(localized: "Saves")) {
                    if !saves.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(saves.prefix(8)) { save in
                                    Button { showingSaves = true } label: {
                                        SaveCard(game: current,
                                                 image: SaveThumbnails.image(for: save, gameID: current.id),
                                                 title: SaveThumbnails.displayName(save),
                                                 detail: save.modified.formatted(.relative(presentation: .named)),
                                                 compact: true)
                                        .frame(width: 124)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(14)
                        }
                        Divider().padding(.leading, 48)
                    }
                    SheetRow(icon: "square.stack", title: saves.isEmpty ? String(localized: "Importar ou ver saves")
                                                                         : String(localized: "Ver todos os saves"),
                             value: saves.isEmpty ? nil : "\(saves.count)", chevron: "chevron.right") {
                        showingSaves = true
                    }
                }

                group(String(localized: "Ajustes deste jogo")) {
                    SheetRow(icon: ControllerTypeStore.type(for: current).icon,
                             title: String(localized: "Controle na tela"),
                             value: ControllerTypeStore.type(for: current).title,
                             chevron: "chevron.right") {
                        choosingController = true
                    }
                    Divider().padding(.leading, 48)
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
                        SheetRowLabel(icon: "gamecontroller", title: String(localized: "Controles"),
                                      value: ProfileStore.shared.profile(for: current).name, chevron: "chevron.up.chevron.down")
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 48)
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
                        SheetRowLabel(icon: "chevron.left.forwardslash.chevron.right", title: String(localized: "Versão do Ruby"),
                                      value: RubyChoice.label(for: current.rubyVersion), chevron: "chevron.up.chevron.down")
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 48)
                    Toggle(isOn: Binding(get: { InGameKeyboard.isOn(for: current.id) }, set: { on in
                        InGameKeyboard.set(on, for: current.id)
                        library.reload()
                        show(on ? String(localized: "O jogo vai usar o próprio teclado na próxima vez que abrir")
                                : String(localized: "O Ember volta a usar o teclado do iPhone"))
                    })) {
                        SheetRowLabel(icon: "keyboard", title: String(localized: "Teclado do próprio jogo"))
                    }
                    .tint(Theme.active)
                    .padding(.trailing, 14)
                    if GameCovers.hasCustomCover(current.id) {
                        Divider().padding(.leading, 48)
                        SheetRow(icon: "arrow.uturn.backward", title: String(localized: "Voltar à capa automática")) {
                            library.removeCustomCover(for: current)
                            show(String(localized: "Capa automática de volta"))
                        }
                    }
                }

                group(String(localized: "Mais")) {
                    SheetRow(icon: "doc.text.magnifyingglass", title: String(localized: "Registros")) { showingLogs = true }
                    Divider().padding(.leading, 48)
                    SheetRow(icon: "trash", title: String(localized: "Apagar jogo"), destructive: true) { confirmingDelete = true }
                }

                // verbatim: a plain Text reads the string as Markdown, which
                // eats the backslash of %APPDATA%\.
                Text(verbatim: String(localized: "No PC, os saves ficam na pasta do jogo (Save1.rxdata, Save01.rvdata2) ou, nos fangames de Pokémon, em %APPDATA%\\\(current.originalTitle) (Game.rxdata). O Ember usa os mesmos arquivos."))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
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
        .onAppear {
            refreshSaves()
            #if DEBUG
            // Development aid: EMBER_SHOW=saves opens the saves screen.
            if ProcessInfo.processInfo.environment["EMBER_SHOW"] == "saves" { showingSaves = true }
            #endif
        }
        .onChange(of: photo) { loadPhoto() }
        .alert("Renomear", isPresented: $renaming) {
            TextField(current.originalTitle, text: $newTitle)
            Button("Cancelar", role: .cancel) {}
            Button("Salvar") { library.rename(current, to: newTitle) }
        } message: {
            Text("Muda só o nome na biblioteca. A pasta e os saves continuam iguais.")
        }
        .sheet(isPresented: $choosingController, onDismiss: { library.reload() }) {
            ControllerChoiceView(game: current)
        }
        .sheet(isPresented: $showingSaves, onDismiss: refreshSaves) {
            SavesView(game: current)
        }
        .sheet(isPresented: $showingLogs) {
            LogsView(game: current)
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(url: file.url)
        }
        .confirmationDialog("Arquivar \(current.title) no iCloud?", isPresented: $confirmingArchive, titleVisibility: .visible) {
            Button("Arquivar") {
                LibraryStore.shared.archive(current)
                dismiss()
            }
        } message: {
            Text("O jogo vai para o iCloud Drive (pasta Ember) e sai do iPhone, liberando \(ByteCountFormatter.string(fromByteCount: EmberBackup.size(of: current.folder), countStyle: .file)). Saves, estados, capa e histórico ficam. Para jogar de novo, toque nele na estante.")
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

    /// Four things people do often, one tap each.
    private var quickActions: some View {
        HStack(spacing: 10) {
            SheetQuickAction(icon: "pencil", title: String(localized: "Renomear")) {
                newTitle = current.title
                renaming = true
            }
            PhotosPicker(selection: $photo, matching: .images) {
                SheetQuickActionLabel(icon: "photo", title: String(localized: "Capa"))
            }
            .buttonStyle(.plain)
            SheetQuickAction(icon: "iphone.radiowaves.left.and.right", title: String(localized: "Enviar saves")) {
                shareSaves()
            }
            SheetQuickAction(icon: "icloud.and.arrow.up", title: String(localized: "Arquivar")) {
                confirmingArchive = true
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(.uppercase)
                Spacer()
                if title == String(localized: "Saves"), working { ProgressView() }
            }
            .padding(.leading, 6)
            VStack(spacing: 0) { content() }
                .emberGlass(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    /// Saves for another iPhone: an .embersave package in the share
    /// sheet. Bringing two iPhones together there starts AirDrop.
    private func shareSaves() {
        let game = current
        working = true
        Task.detached(priority: .userInitiated) {
            let result = Result { try SaveShare.package(game) }
            await MainActor.run {
                working = false
                switch result {
                case .success(let url): exportFile = ExportFile(url: url)
                case .failure(let error): show(error.localizedDescription)
                }
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
}

private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// One of the four round buttons under "Jogar".
private struct SheetQuickAction: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            SheetQuickActionLabel(icon: icon, title: title)
        }
        .buttonStyle(.plain)
    }
}

private struct SheetQuickActionLabel: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 54, height: 54)
                .emberGlass(.regular.interactive(), in: Circle())
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// A row inside a grouped card: icon, title, optional value.
private struct SheetRow: View {
    let icon: String
    let title: String
    var value: String?
    var chevron: String?
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            SheetRowLabel(icon: icon, title: title, value: value, destructive: destructive, chevron: chevron)
        }
        .buttonStyle(.plain)
    }
}

private struct SheetRowLabel: View {
    let icon: String
    let title: String
    var value: String?
    var destructive = false
    var chevron: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(destructive ? Theme.accent : Theme.secondaryText)
                .frame(width: 22)
            Text(title)
                .font(.body)
                .foregroundStyle(destructive ? Theme.accent : Theme.primaryText)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            if let chevron {
                Image(systemName: chevron)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
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
