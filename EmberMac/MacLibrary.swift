import AppKit
import Observation

/// The shelf on the Mac: the same folders as on iPhone (Documents/Games,
/// UserData, Application Support), read by the shared GameEntry, with
/// saves kept in step with iCloud (SaveSync). Each game plays in its own
/// instance of the app (`play`).
@MainActor
@Observable
final class MacLibrary {
    static let shared = MacLibrary()

    private(set) var games: [GameEntry] = []
    /// Names of what is being imported right now.
    private(set) var importing: [String] = []
    var lastError: String?
    var notice: String?
    private(set) var syncing = false
    /// A game asked to open while a newer save is coming down.
    var incomingFor: (game: GameEntry, resume: Bool)?
    private(set) var waitingForSave = false

    private init() {
        SaveSync.deviceName = Host.current().localizedName ?? "Mac"
        reload()
        syncSaves()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            // A game that ran in its own instance wrote history, covers
            // and saves meanwhile.
            MainActor.assumeIsolated {
                MacLibrary.shared.reload()
                MacLibrary.shared.syncSaves()
            }
        }
    }

    func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: GameImporter.gamesFolder, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        games = folders
            .compactMap(GameEntry.init(folder:))
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Played most recently first.
    var recent: [GameEntry] {
        games.filter { $0.lastPlayed != nil }.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
    }

    // MARK: - Playing

    /// Opens the game in a new instance of Ember: a fresh engine, its own
    /// window, and the library stays open.
    /// A sandboxed app cannot pass arguments to a new instance of
    /// itself, so the game goes in a link only Ember opens:
    /// ember-play://play?id=<id>&resume=1.
    func play(_ game: GameEntry, resume: Bool = false, checked: Bool = false) {
        // A newer save from the iPhone still coming down: ask first.
        if !checked, SaveSync.isEnabled {
            Task {
                let folders = SaveSync.GameFolders(game)
                let incoming = await Task.detached(priority: .userInitiated) { SaveSync.hasIncoming(folders) }.value
                if incoming { incomingFor = (game, resume) } else { play(game, resume: resume, checked: true) }
            }
            return
        }
        var link = URLComponents()
        link.scheme = "ember-play"
        link.host = "play"
        link.queryItems = [URLQueryItem(name: "id", value: game.id)] + (resume ? [URLQueryItem(name: "resume", value: "1")] : [])
        #if DEBUG
        if let script = ProcessInfo.processInfo.environment["EMBER_SCRIPT"] {
            link.queryItems?.append(URLQueryItem(name: "script", value: script))
        }
        if ProcessInfo.processInfo.environment["EMBER_MUTE"] != nil {
            link.queryItems?.append(URLQueryItem(name: "mute", value: "1"))
        }
        #endif
        guard let url = link.url else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.open([url], withApplicationAt: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard let error else { return }
            Task { @MainActor in MacLibrary.shared.lastError = error.localizedDescription }
        }
    }

    /// The game instance sends its saves to iCloud as it quits; the
    /// library says so when it comes back to the front right after.
    private var announced: UUID?

    func announceFinishedGame() {
        guard let last = PlayHistory.sessions.first, last.id != announced,
              Date().timeIntervalSince(last.end) < 90,
              SyncStatus.shared.state(for: last.gameID) == .upToDate else { return }
        announced = last.id
        SyncStatus.shared.show(String(localized: "Save sincronizado: \(last.title)"))
    }

    func waitThenPlay() {
        guard let pending = incomingFor else { return }
        incomingFor = nil
        waitingForSave = true
        Task {
            let arrived = await SyncStatus.waitForIncoming(pending.game)
            waitingForSave = false
            reload()
            if !arrived { SyncStatus.shared.show(String(localized: "O save ainda não chegou. Abrindo com o que está aqui.")) }
            play(games.first { $0.id == pending.game.id } ?? pending.game, resume: pending.resume, checked: true)
        }
    }

    func playAnyway() {
        guard let pending = incomingFor else { return }
        incomingFor = nil
        play(pending.game, resume: pending.resume, checked: true)
    }

    // MARK: - Importing

    /// Games (.zip, .rar, .7z, .exe, folders) and RTPs, one after another
    /// off the main thread.
    func importItems(_ urls: [URL]) {
        for url in urls {
            let name = url.lastPathComponent
            guard !importing.contains(name) else { continue }
            importing.append(name)
            Task.detached(priority: .userInitiated) {
                let result = Result { try GameImporter.importItem(at: url) }
                await MainActor.run {
                    let library = MacLibrary.shared
                    library.importing.removeAll { $0 == name }
                    switch result {
                    case .success(.game(let id)):
                        library.reload()
                        if let game = library.games.first(where: { $0.id == id }) {
                            Task { await ControllerTypeStore.detect([game]) }
                        }
                    case .success(.rtp(let kind)):
                        library.notice = String(localized: "RTP do \(kind.name) instalado. Os jogos dessa versão já usam os gráficos e sons dele.")
                    case .failure(let error):
                        library.lastError = error.localizedDescription
                    }
                }
            }
        }
    }

    /// The demo game that ships inside the app (A Última Brasa).
    var hasDemo: Bool {
        guard let folder = Bundle.main.url(forResource: "EmberDemo", withExtension: nil),
              let title = GameFolder.title(in: folder) else { return false }
        return games.contains { $0.originalTitle == title }
    }

    func installDemo() {
        guard let folder = Bundle.main.url(forResource: "EmberDemo", withExtension: nil), !hasDemo else { return }
        importItems([folder])
    }

    func delete(_ game: GameEntry) {
        SaveManager.stashGameFolderSaves(of: game)
        do {
            try FileManager.default.removeItem(at: game.folder)
        } catch {
            lastError = String(localized: "Não deu para apagar “\(game.title)”: \(error.localizedDescription)")
        }
        reload()
    }

    // MARK: - iCloud

    func syncSaves(attempt: Int = 0) {
        guard SaveSync.isEnabled, !syncing, !games.isEmpty else { return }
        let folders = games.map { game in
            SaveSync.GameFolders(id: game.id, title: game.title, folder: game.folder,
                                 userData: GameStorage.userDataFolder(for: game),
                                 states: StateStore.folder(for: game.id))
        }
        let titles = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0.title) })
        syncing = true
        SyncStatus.shared.began()
        Task.detached(priority: .utility) {
            let report = SaveSync.sync(folders)
            await MainActor.run {
                let library = MacLibrary.shared
                library.syncing = false
                SyncStatus.shared.finished(report, titles: titles)
                library.announceFinishedGame()
                if report.downloaded > 0 { library.reload() }
                if !report.conflicts.isEmpty {
                    let titles = Array(Set(report.conflicts)).sorted().joined(separator: ", ")
                    library.notice = String(localized: "\(titles) teve saves mudados aqui e em outro aparelho. Ficou o mais recente; o outro está guardado em Backups.")
                }
                if report.waiting > 0, attempt < 10 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        MacLibrary.shared.syncSaves(attempt: attempt + 1)
                    }
                }
            }
        }
    }
}
