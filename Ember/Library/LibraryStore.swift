import Foundation
import SwiftUI
import UIKit

/// The games in Documents/Games, and the imports into it.
@MainActor
@Observable
final class LibraryStore {
    static let shared = LibraryStore()

    private(set) var games: [GameEntry] = []
    /// Games archived in iCloud (Arquivar no iCloud).
    private(set) var archived: [ArchivedGame] = []
    /// What an archive or restore is doing right now, by game id.
    private(set) var archiveStatus: [String: String] = [:]
    /// Its progress (0...1), when known.
    private(set) var archiveProgress: [String: Double] = [:]
    @ObservationIgnored private var cloudWatch: ObservationLoop?
    /// Names of the items being imported right now.
    private(set) var importing: [String] = []
    var lastError: String?
    /// Set when a skin arrived through an import, for a confirmation.
    var importedSkinName: String?
    /// A confirmation to show after an import that is not a game (an
    /// RTP, saves from another iPhone).
    var importNotice: Notice?
    /// A game just imported: Ember asks which controller it gets.
    var chooseController: GameEntry?
    /// A game just imported that looks like a new version of one on the
    /// shelf: the library asks whether to update it.
    var updateOffer: GameUpdater.Offer?
    /// Saves going to or coming from iCloud right now.
    private(set) var syncingSaves = false
    private(set) var lastSaveSync: (date: Date, report: SaveSync.Report)?

    struct Notice: Equatable {
        let title: String
        let message: String
    }

    /// The game to offer under "Continuar": the last one played.
    var recent: GameEntry? {
        games.filter { $0.lastPlayed != nil }.max { $0.lastPlayed! < $1.lastPlayed! }
    }

    private init() {
        SaveSync.deviceName = UIDevice.current.name
        reload()
        importFromDocumentsRoot()
        syncSaves()
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                // Games may have arrived through the Finder while the
                // app was away.
                guard EngineSession.shared.state != .running else { return }
                LibraryStore.shared.reload()
                LibraryStore.shared.importFromDocumentsRoot()
                LibraryStore.shared.syncSaves()
            }
        }
    }

    func reload() {
        let folder = GameImporter.gamesFolder
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        games = folders
            .compactMap(GameEntry.init(folder:))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        archived = GameArchive.records().filter { record in !games.contains { $0.id == record.id } }
        watchUploads()
        QuickAction.refresh(self)
        // Games imported before controller types: read their scripts.
        let current = games
        Task { await ControllerTypeStore.detect(current) }
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
            // Once per file: the app becoming active looks at Documents
            // again while a restore may still run.
            let name = url.lastPathComponent
            guard !importing.contains(name) else { continue }
            importing.append(name)
            let existing = Set(games.map(\.id))
            Task.detached(priority: .userInitiated) {
                let outcome = Result { try EmberBackup.restore(url, keepingGames: existing) }
                // A backup left in Documents would be restored again
                // each time the app comes back.
                if removeSources, case .success = outcome {
                    try? FileManager.default.removeItem(at: url)
                }
                await MainActor.run {
                    self.importing.removeAll { $0 == name }
                    self.reload()
                    SkinStore.shared.reload()
                    ProfileStore.shared.reloadFromDefaults()
                    switch outcome {
                    case .success(let summary):
                        var message = String(localized: "Backup restaurado: \(summary.games) jogos e \(summary.files) arquivos.")
                        if summary.waitingSaves > 0 {
                            message += " " + String(localized: "Os saves de jogos que não estão neste aparelho ficaram em Backups. Importe o jogo e depois os saves.")
                        }
                        self.importNotice = Notice(title: String(localized: "Backup restaurado"), message: message)
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
                    if case .success(.game(let id)) = result,
                       let game = self.games.first(where: { $0.id == id }) {
                        if let existing = GameUpdater.existingVersion(of: game, in: self.games) {
                            self.updateOffer = GameUpdater.Offer(incoming: game, existing: existing)
                            return
                        }
                        Task {
                            await ControllerTypeStore.detect([game])
                            if url.lastPathComponent == "EmberDemo" {
                                // The demo needs two buttons; no question.
                                ControllerTypeStore.markAsked(game.id)
                            } else if ControllerTypeStore.needsChoice(game) {
                                self.chooseController = game
                            }
                        }
                    }
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

    /// Brings saves in step with iCloud (`SaveSync`), off the main
    /// thread. Never while a game runs: it reads and writes its saves.
    func syncSaves(attempt: Int = 0, announce: Bool = false) {
        guard SaveSync.isEnabled, !syncingSaves, EngineSession.shared.state != .running, !games.isEmpty else { return }
        let folders = games.map { game in
            SaveSync.GameFolders(id: game.id, title: game.title, folder: game.folder,
                                 userData: GameStorage.userDataFolder(for: game),
                                 states: StateStore.folder(for: game.id))
        }
        let titles = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0.title) })
        syncingSaves = true
        SyncStatus.shared.began()
        Task.detached(priority: .utility) {
            let report = SaveSync.sync(folders)
            await MainActor.run {
                self.syncingSaves = false
                self.lastSaveSync = (Date(), report)
                SyncStatus.shared.finished(report, titles: titles, announceUploads: announce)
                if report.downloaded > 0 { self.reload() }
                if !report.conflicts.isEmpty {
                    let titles = Array(Set(report.conflicts)).sorted().joined(separator: ", ")
                    self.importNotice = Notice(
                        title: String(localized: "Saves de dois aparelhos"),
                        message: String(localized: "\(titles) teve saves mudados aqui e em outro aparelho. Ficou o mais recente; o outro está guardado em Backups."))
                }
                // Saves still coming down from iCloud: look again soon
                // instead of waiting for the next time Ember opens.
                if report.waiting > 0, attempt < 10 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        self.syncSaves(attempt: attempt + 1, announce: announce)
                    }
                }
            }
        }
    }

    /// Puts a new version in the old game's place (saves, states and
    /// settings stay).
    func applyUpdate(_ offer: GameUpdater.Offer) {
        updateOffer = nil
        importing.append(offer.incoming.title)
        Task.detached(priority: .userInitiated) {
            let result = Result { try GameUpdater.update(offer) }
            await MainActor.run {
                self.importing.removeAll { $0 == offer.incoming.title }
                self.reload()
                switch result {
                case .success:
                    // The new version's scripts may read other keys.
                    ControllerTypeStore.forgetDetection(offer.existing.id)
                    ControllerTypeStore.forget(offer.incoming.id)
                    Haptics.success()
                    self.importNotice = Notice(
                        title: String(localized: "Jogo atualizado"),
                        message: String(localized: "“\(offer.existing.title)” agora está na versão nova. Saves, estados e controles continuam."))
                    if let game = self.games.first(where: { $0.id == offer.existing.id }) {
                        Task { await ControllerTypeStore.detect([game]) }
                    }
                case .failure(let error):
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    /// Keeps both: the new version stays as its own game.
    func keepBoth(_ offer: GameUpdater.Offer) {
        updateOffer = nil
        let game = offer.incoming
        Task {
            await ControllerTypeStore.detect([game])
            if ControllerTypeStore.needsChoice(game) { self.chooseController = game }
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
        withAnimation { archiveStatus[game.id] = String(localized: "Compactando…") }
        Task.detached(priority: .userInitiated) {
            let result = Result { try GameArchive.archive(game) }
            await MainActor.run {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    self.archiveStatus[game.id] = nil
                    if case .failure(let error) = result { self.lastError = error.localizedDescription }
                    self.reload()
                }
            }
        }
    }

    /// While a pack uploads, its card says so with the percentage; once
    /// iCloud has it, the local copy is freed.
    private func watchUploads() {
        let pending = archived.filter { !GameArchive.isUploaded($0) }
        for record in pending where archiveStatus[record.id] == nil {
            archiveStatus[record.id] = String(localized: "Enviando ao iCloud…")
        }
        guard cloudWatch == nil, !pending.isEmpty else { return }
        cloudWatch = ObservationLoop(read: { _ = CloudProgress.shared.items }) { [weak self] in
            self?.showUploads(CloudProgress.shared.items)
        }
        showUploads(CloudProgress.shared.items)
    }

    private func showUploads(_ items: [String: CloudProgress.Item]) {
        var stillUploading = false
        for record in archived {
            guard let item = items[record.archiveName] else { continue }
            if item.isUploaded {
                if archiveStatus[record.id] == String(localized: "Enviando ao iCloud…") {
                    withAnimation {
                        archiveStatus[record.id] = nil
                        archiveProgress[record.id] = nil
                    }
                }
            } else {
                stillUploading = true
                archiveProgress[record.id] = item.uploaded.map { $0 / 100 }
            }
        }
        if !stillUploading {
            Task.detached(priority: .utility) { GameArchive.evictUploaded() }
            cloudWatch?.cancel()
            cloudWatch = nil
        }
    }

    func unarchive(_ record: ArchivedGame) {
        guard archiveStatus[record.id] == nil else { return }
        withAnimation { archiveStatus[record.id] = String(localized: "Preparando…") }
        Task.detached(priority: .userInitiated) {
            let result: Result<Void, Error>
            do {
                try await GameArchive.restore(record) { status, fraction in
                    Task { @MainActor in
                        self.archiveStatus[record.id] = status
                        self.archiveProgress[record.id] = fraction
                    }
                }
                result = .success(())
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    self.archiveStatus[record.id] = nil
                    self.archiveProgress[record.id] = nil
                    if case .failure(let error) = result { self.lastError = error.localizedDescription }
                    self.reload()
                }
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
        ControllerTypeStore.forget(game.id)
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
