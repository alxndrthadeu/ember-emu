import Foundation

/// The games in Documents/Games, and the imports into it.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var games: [GameEntry] = []
    /// Names of the items being imported right now.
    @Published private(set) var importing: [String] = []
    @Published var lastError: String?

    private init() { reload() }

    func reload() {
        let folder = GameImporter.gamesFolder
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        games = folders
            .compactMap(GameEntry.init(folder:))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Imports items one after another, off the main thread: a big
    /// game takes a few seconds to unzip.
    func importItems(_ urls: [URL]) {
        for url in urls {
            let name = url.lastPathComponent
            importing.append(name)
            Task.detached(priority: .userInitiated) {
                let result = Result { try GameImporter.importItem(at: url) }
                await MainActor.run {
                    self.importing.removeAll { $0 == name }
                    if case .failure(let error) = result {
                        self.lastError = error.localizedDescription
                    }
                    self.reload()
                }
            }
        }
    }

    /// Removes the game's files. Saves stay in UserData/<id>, so
    /// importing the same game again brings them back.
    func delete(_ game: GameEntry) {
        do {
            try FileManager.default.removeItem(at: game.folder)
        } catch {
            lastError = "Não deu para apagar “\(game.title)”: \(error.localizedDescription)"
        }
        reload()
    }
}
