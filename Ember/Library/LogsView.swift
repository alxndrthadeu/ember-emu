import SwiftUI

/// A game's session logs, newest first, plus the error log the game
/// itself writes (Pokémon Essentials' errorlog.txt).
struct LogsView: View {
    let game: GameEntry

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [Entry] = []

    struct Entry: Identifiable, Hashable {
        let url: URL
        let title: String
        let subtitle: String
        let hasError: Bool
        var id: URL { url }
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("Nenhum registro ainda", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("Cada vez que o jogo abre, o Ember guarda o que aconteceu: erros, avisos e o que o motor escreveu.")
                    }
                } else {
                    List(entries) { entry in
                        NavigationLink {
                            LogTextView(url: entry.url, title: entry.title)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: entry.hasError ? "exclamationmark.triangle.fill" : "doc.text")
                                    .foregroundStyle(entry.hasError ? Theme.accent : Theme.secondaryText)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.title)
                                        .font(.body.weight(.semibold))
                                    Text(entry.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Registros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Fechar")
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        var list: [Entry] = []
        let fm = FileManager.default
        // The game's own error log, when it keeps one.
        let gameLog = GameStorage.userDataFolder(for: game).appendingPathComponent("errorlog.txt")
        if fm.fileExists(atPath: gameLog.path) {
            list.append(Entry(url: gameLog, title: String(localized: "Erros registrados pelo jogo"),
                              subtitle: modified(gameLog), hasError: true))
        }
        let sessions = ((try? fm.contentsOfDirectory(at: GameLog.folder(for: game.id),
                                                      includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for url in sessions {
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let errors = text.components(separatedBy: "\n").filter { $0.hasPrefix(GameLog.errorMarker) }.count
            let size = ByteCountFormatter.string(fromByteCount: Int64(text.utf8.count), countStyle: .file)
            list.append(Entry(url: url, title: String(localized: "Sessão de \(modified(url))"),
                              subtitle: errors > 0 ? String(localized: "\(errors) erro(s) · \(size)") : size,
                              hasError: errors > 0))
        }
        entries = list
    }

    private func modified(_ url: URL) -> String {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// A log's text, with errors first when there are any, and a share button.
private struct LogTextView: View {
    let url: URL
    let title: String

    @State private var text = ""
    @State private var onlyErrors = false

    private var shown: String {
        guard onlyErrors else { return text }
        let lines = text.components(separatedBy: "\n").filter {
            $0.hasPrefix(GameLog.errorMarker) || $0.localizedCaseInsensitiveContains("error")
                || $0.localizedCaseInsensitiveContains("exception")
        }
        return lines.isEmpty ? String(localized: "Nenhum erro nesta sessão.") : lines.joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            Text(shown)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $onlyErrors) {
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .toggleStyle(.button)
                .accessibilityLabel("Só erros")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .onAppear {
            text = (try? String(contentsOf: url, encoding: .utf8))
                ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? ""
        }
    }
}
