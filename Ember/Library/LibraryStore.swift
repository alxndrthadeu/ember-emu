import Foundation
import UIKit

/// The games in Documents/Games, and the imports into it.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var games: [GameEntry] = []
    /// Games archived in iCloud (Arquivar no iCloud).
    @Published private(set) var archived: [ArchivedGame] = []
    /// What an archive or restore is doing right now, by game id.
    @Published private(set) var archiveStatus: [String: String] = [:]
    /// Names of the items being imported right now.
    @Published private(set) var importing: [String] = []
    @Published var lastError: String?
    /// Set when a skin arrived through an import, for a confirmation.
    @Published var importedSkinName: String?
    /// A confirmation to show after an import that is not a game (an
    /// RTP, saves from another iPhone).
    @Published var importNotice: Notice?

    struct Notice: Equatable {
        let title: String
        let message: String
    }

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
        archived = GameArchive.records().filter { record in !games.contains { $0.id == record.id } }
        QuickAction.refresh(self)
        // Packs iCloud already has no longer need their local copy.
        if !archived.isEmpty {
            Task.detached(priority: .utility) { GameArchive.evictUploaded() }
        }
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
        // Saves sent from another iPhone go into their game.
        let saves = urls.filter { $0.pathExtension.lowercased() == SaveShare.fileExtension }
        for url in saves {
            do {
                let (game, count) = try SaveShare.receive(url)
                if removeSources { try? FileManager.default.removeItem(at: url) }
                importNotice = Notice(
                    title: String(localized: "Saves recebidos"),
                    message: count == 1
                        ? String(localized: "1 save de “\(game.title)” chegou. Os saves que já estavam aqui foram guardados em Backups.")
                        : String(localized: "\(count) saves de “\(game.title)” chegaram. Os saves que já estavam aqui foram guardados em Backups."))
            } catch {
                lastError = error.localizedDescription
            }
        }
        // A whole Ember backup ("Open in Ember", the Finder, Files).
        let backups = urls.filter { $0.pathExtension.lowercased() == EmberBackup.fileExtension }
        for url in backups {
            let existing = Set(games.map(\.id))
            Task.detached(priority: .userInitiated) {
                let outcome = Result { try EmberBackup.restore(url, keepingGames: existing) }
                await MainActor.run {
                    self.reload()
                    SkinStore.shared.reload()
                    switch outcome {
                    case .success(let summary):
                        self.importNotice = Notice(
                            title: String(localized: "Backup restaurado"),
                            message: String(localized: "Backup restaurado: \(summary.games) jogos e \(summary.files) arquivos."))
                    case .failure(let error):
                        self.lastError = error.localizedDescription
                    }
                }
            }
        }
        let discard = AppSettings.deleteArchiveAfterImport
        for url in urls where !skins.contains(url) && !saves.contains(url) && !backups.contains(url) {
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
                    switch result {
                    case .failure(let error):
                        self.lastError = error.localizedDescription
                    case .success(.rtp(let kind)):
                        self.importNotice = Notice(
                            title: String(localized: "RTP instalado"),
                            message: String(localized: "RTP do \(kind.name) instalado. Os jogos dessa versão já usam os gráficos e sons dele."))
                    case .success(.game):
                        break
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
                    || ext == SaveShare.fileExtension || ext == EmberBackup.fileExtension
                    || (isFolder && (GameFolder.findRoot(in: url) != nil || RTPStore.findRoot(in: url) != nil)) {
                    candidates.append(url)
                }
            }
        }
        if !candidates.isEmpty {
            importItems(candidates, removeSources: true)
        }
    }

    /// The demo game that ships inside the app (A Última Brasa).
    static var demoFolder: URL? {
        Bundle.main.url(forResource: "EmberDemo", withExtension: nil)
    }

    var hasDemo: Bool {
        guard let folder = Self.demoFolder, let title = GameFolder.title(in: folder) else { return false }
        return games.contains { $0.originalTitle == title }
    }

    /// Copies the demo into the library, once.
    func installDemo() {
        guard let folder = Self.demoFolder, !hasDemo else { return }
        importItems([folder])
    }

    // MARK: - iCloud archive

    func archive(_ game: GameEntry) {
        guard archiveStatus[game.id] == nil else { return }
        archiveStatus[game.id] = String(localized: "Compactando…")
        Task.detached(priority: .userInitiated) {
            let result = Result { try GameArchive.archive(game) }
            await MainActor.run {
                self.archiveStatus[game.id] = nil
                if case .failure(let error) = result { self.lastError = error.localizedDescription }
                self.reload()
            }
            // Free the local copy once iCloud has it.
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(10))
                GameArchive.evictUploaded()
            }
        }
    }

    func unarchive(_ record: ArchivedGame) {
        guard archiveStatus[record.id] == nil else { return }
        archiveStatus[record.id] = String(localized: "Preparando…")
        Task.detached(priority: .userInitiated) {
            let result: Result<Void, Error>
            do {
                try await GameArchive.restore(record) { status in
                    Task { @MainActor in self.archiveStatus[record.id] = status }
                }
                result = .success(())
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                self.archiveStatus[record.id] = nil
                if case .failure(let error) = result { self.lastError = error.localizedDescription }
                self.reload()
            }
        }
    }

    func deleteArchived(_ record: ArchivedGame) {
        Task.detached(priority: .utility) {
            GameArchive.delete(record)
            await MainActor.run { self.reload() }
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
            lastError = String(localized: "Não deu para apagar “\(game.title)”: \(error.localizedDescription)")
        }
        reload()
    }
}
