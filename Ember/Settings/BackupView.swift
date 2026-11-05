import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension UTType {
    static let emberBackup = UTType(exportedAs: "com.alexandrethadeu.ember.backup")
}

/// Ajustes › Backup: the two actions.
struct BackupSection: View {
    @ObservedObject private var library = LibraryStore.shared
    @State private var picking = false
    @State private var restoring: URL?
    @State private var working = false
    @State private var result: String?

    var body: some View {
        Section {
            NavigationLink {
                BackupBuilderView()
            } label: {
                Label("Fazer backup…", systemImage: "externaldrive.badge.icloud")
            }
            Button {
                picking = true
            } label: {
                HStack {
                    Label("Restaurar um backup…", systemImage: "clock.arrow.circlepath")
                    if working {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(working)
        } header: {
            Text("Backup")
        } footer: {
            Text("Escolha o que guardar e salve o arquivo .emberbackup onde quiser: iCloud Drive, Google Drive, Dropbox ou no computador, pelo app Arquivos.")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.emberBackup, .zip, .data]) { picked in
            if case .success(let url) = picked { restoring = url }
        }
        .confirmationDialog("Restaurar este backup?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
                            titleVisibility: .visible) {
            Button("Restaurar") {
                if let url = restoring { restore(url) }
            }
        } message: {
            Text("Jogos que não estão aqui voltam inteiros. Nos que já estão, só os saves voltam. O que for substituído fica guardado em Backups, no app Arquivos.")
        }
        .alert("Backup", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(result ?? "")
        }
    }

    private func restore(_ url: URL) {
        working = true
        let existing = Set(library.games.map(\.id))
        Task.detached(priority: .userInitiated) {
            let outcome = Result { try EmberBackup.restore(url, keepingGames: existing) }
            await MainActor.run {
                working = false
                LibraryStore.shared.reload()
                SkinStore.shared.reload()
                switch outcome {
                case .success(let summary):
                    result = String(localized: "Backup restaurado: \(summary.games) jogos e \(summary.files) arquivos.")
                case .failure(let error):
                    result = error.localizedDescription
                }
            }
        }
    }
}

/// Picks what goes into a backup, shows the size, and saves the file.
struct BackupBuilderView: View {
    @ObservedObject private var library = LibraryStore.shared
    @State private var options = EmberBackup.Options()
    @State private var sizes: (games: [String: Int64], saves: Int64, states: Int64,
                               covers: Int64, rtp: Int64, skins: Int64)?
    @State private var working = false
    @State private var exportURL: URL?
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                ForEach(library.games) { game in
                    Toggle(isOn: Binding(get: { options.games.contains(game.id) },
                                         set: { on in
                                             if on { options.games.insert(game.id) } else { options.games.remove(game.id) }
                                         })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(game.title)
                            Text(sizeText(sizes?.games[game.id]))
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Jogos")
                    Spacer()
                    Button(options.games.count == library.games.count ? "Nenhum" : "Todos") {
                        options.games = options.games.count == library.games.count ? [] : Set(library.games.map(\.id))
                    }
                    .font(.caption.weight(.semibold))
                    .textCase(nil)
                }
            } footer: {
                Text("Jogo desmarcado não entra, mas os saves dele entram se \"Saves\" estiver ligado.")
            }

            Section("Progresso e ajustes") {
                toggle("Saves", detail: sizes?.saves, isOn: $options.saves)
                toggle("Estados salvos", detail: sizes?.states, isOn: $options.states)
                toggle("Capas", detail: sizes?.covers, isOn: $options.covers)
                toggle("Skins", detail: sizes?.skins, isOn: $options.skins)
                toggle("RTP", detail: sizes?.rtp, isOn: $options.rtp)
                Toggle("Ajustes, nomes e histórico", isOn: $options.settings)
            }

            Section {
                Button {
                    make()
                } label: {
                    HStack {
                        Label("Fazer backup", systemImage: "square.and.arrow.down.on.square")
                        Spacer()
                        if working { ProgressView() } else {
                            Text(sizeText(total)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                .disabled(working || options.isEmpty)
            } footer: {
                Text("Depois, escolha onde salvar. Jogos grandes deixam o backup grande: confira o espaço na nuvem.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Fazer backup")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let games = library.games
            let measured = await Task.detached(priority: .utility) { EmberBackup.sizes(games) }.value
            sizes = measured
        }
        .sheet(item: Binding(get: { exportURL.map(ExportTarget.init) }, set: { exportURL = $0?.url })) { target in
            DocumentExporter(url: target.url)
                .ignoresSafeArea()
        }
        .alert("Não deu certo", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private var total: Int64? {
        guard let sizes else { return nil }
        var sum: Int64 = options.games.reduce(0) { $0 + (sizes.games[$1] ?? 0) }
        if options.saves { sum += sizes.saves }
        if options.states { sum += sizes.states }
        if options.covers { sum += sizes.covers }
        if options.rtp { sum += sizes.rtp }
        if options.skins { sum += sizes.skins }
        return sum
    }

    private func toggle(_ title: LocalizedStringKey, detail: Int64?, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack {
                Text(title)
                Spacer()
                Text(sizeText(detail))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func sizeText(_ bytes: Int64?) -> String {
        guard let bytes else { return "…" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func make() {
        working = true
        let options = options
        let games = library.games
        Task.detached(priority: .userInitiated) {
            let made = Result { try EmberBackup.make(options, library: games) }
            await MainActor.run {
                working = false
                switch made {
                case .success(let url): exportURL = url
                case .failure(let failure): error = failure.localizedDescription
                }
            }
        }
    }
}

private struct ExportTarget: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// "Save to Files": moves the finished backup where the player picks
/// (no second copy on the iPhone).
private struct DocumentExporter: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        UIDocumentPickerViewController(forExporting: [url], asCopy: false)
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
}
