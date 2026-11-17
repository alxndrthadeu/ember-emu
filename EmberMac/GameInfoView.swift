import SwiftUI
import UniformTypeIdentifiers

/// A game's panel on the Mac (⌘I or right-click › Informações): what the
/// iPhone shows when a game is held. Play, its saves and states, its
/// name, cover and Ruby, and delete.
struct GameInfoView: View {
    let game: GameEntry
    @Environment(\.dismiss) private var dismiss
    @Bindable private var library = MacLibrary.shared
    @State private var title: String
    @State private var ruby: RubyChoice?
    @State private var saves: [SaveManager.SaveFile] = []
    @State private var states: [StateStore.SaveState] = []
    @State private var pickingCover = false
    @State private var importingSaves = false
    @State private var message: String?
    @State private var confirmingDelete = false

    init(game: GameEntry) {
        self.game = game
        _title = State(initialValue: game.title)
        _ruby = State(initialValue: RubyChoice.saved(for: game.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(20)
            Divider()
            Form {
                Section("Saves") {
                    if saves.isEmpty {
                        Text("Ainda não há saves deste jogo.").foregroundStyle(.secondary)
                    }
                    ForEach(saves) { save in
                        LabeledContent(SaveThumbnails.displayName(save),
                                       value: save.modified.formatted(date: .abbreviated, time: .shortened))
                    }
                    HStack {
                        Button("Exportar saves…") { exportSaves() }
                            .disabled(saves.isEmpty)
                        Button("Importar saves…") { importingSaves = true }
                    }
                }
                Section("Estados salvos") {
                    if states.isEmpty {
                        Text("Nenhum estado salvo. No jogo, use Jogo › Salvar estado (⌘S).").foregroundStyle(.secondary)
                    }
                    ForEach(states.prefix(8)) { state in
                        LabeledContent(state.isAuto ? String(localized: "Automático") : String(localized: "Estado"),
                                       value: state.date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Section("Ajustes deste jogo") {
                    TextField("Nome", text: $title)
                        .onSubmit(rename)
                    Picker("Versão do Ruby", selection: $ruby) {
                        Text("Automático (\(RubyChoice.label(for: game.detectedRubyVersion)))").tag(RubyChoice?.none)
                        ForEach(RubyChoice.allCases) { Text("Ruby \($0.label)").tag(RubyChoice?.some($0)) }
                    }
                    .onChange(of: ruby) { RubyChoice.set(ruby, for: game.id) }
                    HStack {
                        Button("Escolher capa…") { pickingCover = true }
                        if GameCovers.hasCustomCover(game.id) {
                            Button("Voltar à capa automática") {
                                GameCovers.removeCustomCover(forGameID: game.id)
                                library.reload()
                            }
                        }
                    }
                }
                Section {
                    Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([game.folder]) }
                    Button("Apagar jogo…", role: .destructive) { confirmingDelete = true }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 640)
        .onAppear(perform: load)
        .onDisappear(perform: rename)
        .fileImporter(isPresented: $pickingCover, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let image = NSImage(contentsOf: url) {
                GameCovers.setCustomCover(image, forGameID: game.id)
                library.reload()
            }
        }
        .fileImporter(isPresented: $importingSaves, allowedContentTypes: [.zip, .folder, .data],
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            do {
                let count = try SaveManager.importSaves(from: urls, into: game)
                message = String(localized: "\(count) arquivo(s) de save importado(s). Os que foram substituídos estão em Backups.")
                load()
            } catch {
                message = error.localizedDescription
            }
        }
        .alert("Ember", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog("Apagar “\(game.title)”?", isPresented: $confirmingDelete) {
            Button("Apagar jogo", role: .destructive) {
                library.delete(game)
                dismiss()
            }
        } message: {
            Text("Os arquivos do jogo saem do Mac. Os saves ficam guardados em Backups.")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            MacCover(game: game)
                .aspectRatio(4 / 3, contentMode: .fit)
                .frame(width: 140)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(game.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                let total = PlayHistory.totalTime(game.id)
                if total >= 60 {
                    Text(Duration.seconds(total).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) + " " + String(localized: "jogados"))
                        .foregroundStyle(Theme.secondaryText)
                }
                if let last = game.lastPlayed {
                    Text("Jogado \(last.formatted(.relative(presentation: .named)))")
                        .foregroundStyle(Theme.secondaryText)
                }
                HStack {
                    Button {
                        library.play(game)
                        dismiss()
                    } label: {
                        Label("Jogar", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    if StateStore.autoState(for: game.id) != nil {
                        Button("Continuar de onde parou") {
                            library.play(game, resume: true)
                            dismiss()
                        }
                    }
                }
                .padding(.top, 6)
            }
            Spacer()
        }
    }

    private func load() {
        saves = SaveManager.saves(for: game)
        states = StateStore.states(for: game.id)
    }

    private func rename() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != game.title else { return }
        TitleOverrides.set(trimmed == game.originalTitle ? nil : trimmed, for: game.id)
        library.reload()
    }

    private func exportSaves() {
        do {
            let file = try SaveManager.export(game)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = file.lastPathComponent
            guard panel.runModal() == .OK, let target = panel.url else { return }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: file, to: target)
        } catch {
            message = error.localizedDescription
        }
    }
}
