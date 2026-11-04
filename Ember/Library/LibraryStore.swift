import Foundation
import UIKit

/// The games in Documents/Games, and the imports into it.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var games: [GameEntry] = []
    /// Names of the items being imported right now.
    @Published private(set) var importing: [String] = []
    @Published var lastError: String?
    /// Set when a skin arrived through an import, for a confirmation.
    @Published var importedSkinName: String?

    /// The game to offer under "Continuar": the last one played.
    var recent: GameEntry? {
        games.filter { $0.lastPlayed != nil }.max { $0.lastPlayed! < $1.lastPlayed! }
    }

    private init() {
        reload()
        importFromDocumentsRoot()
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                // Games may have arrived through the Finder while the
                // app was away.
                guard EngineSession.shared.state != .running else { return }
                LibraryStore.shared.reload()
                LibraryStore.shared.importFromDocumentsRoot()
            }
        }
    }

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
    /// game takes a few seconds to unzip. `removeSources` deletes each
    /// item once imported (files dropped into Ember through the Finder).
    func importItems(_ urls: [URL], removeSources: Bool = false) {
        // Skins can arrive by the same roads (Files, Finder, "Open in").
        let skins = urls.filter { SkinStore.skinExtensions.contains($0.pathExtension.lowercased()) }
        for url in skins {
            do {
                let skin = try SkinStore.shared.importSkin(from: url)
                if removeSources { try? FileManager.default.removeItem(at: url) }
                lastError = nil
                importedSkinName = skin.name
            } catch {
                lastError = error.localizedDescription
            }
        }
        let discard = AppSettings.deleteArchiveAfterImport
        for url in urls where !skins.contains(url) {
            let name = url.lastPathComponent
            guard !importing.contains(name) else { continue }
            importing.append(name)
            Task.detached(priority: .userInitiated) {
                let result = Result {
                    try GameImporter.importItem(at: url, discardArchive: discard && !removeSources)
                }
                if removeSources, case .success = result {
                    try? FileManager.default.removeItem(at: url)
                }
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

    /// The Finder (Mac) and "Open in" drop files at the top of
    /// Documents or in Documents/Inbox. A .zip, or a folder that holds
    /// a game, there becomes a library game.
    func importFromDocumentsRoot() {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let reserved: Set<String> = ["Games", "UserData", "Backups", "Inbox"]
        var candidates: [URL] = []
        for root in [documents, documents.appendingPathComponent("Inbox")] {
            let names = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
            for name in names where !name.hasPrefix(".") && !(root == documents && reserved.contains(name)) {
                let url = root.appendingPathComponent(name)
                let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                let ext = url.pathExtension.lowercased()
                if GameImporter.archiveExtensions.contains(ext) || SkinStore.skinExtensions.contains(ext)
                    || (isFolder && GameFolder.findRoot(in: url) != nil) {
                    candidates.append(url)
                }
            }
        }
        if !candidates.isEmpty {
            importItems(candidates, removeSources: true)
        }
    }

    func rename(_ game: GameEntry, to title: String) {
        TitleOverrides.set(title == game.originalTitle ? nil : title, for: game.id)
        reload()
    }

    func setCover(_ image: UIImage, for game: GameEntry) {
        GameCovers.setCustomCover(image, forGameID: game.id)
        reload()
    }

    func removeCustomCover(for game: GameEntry) {
        GameCovers.removeCustomCover(forGameID: game.id)
        reload()
    }

    /// Removes the game's files. Saves in the game folder move to
    /// Backups first; saves in UserData/<id> stay, and come back if the
    /// game is imported again under the same name.
    func delete(_ game: GameEntry) {
        // Plain RPG Maker games save inside their own folder.
        SaveManager.stashGameFolderSaves(of: game)
        do {
            try FileManager.default.removeItem(at: game.folder)
        } catch {
            lastError = "Não deu para apagar “\(game.title)”: \(error.localizedDescription)"
        }
        reload()
    }
}
