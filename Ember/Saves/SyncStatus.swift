import Foundation
import Observation

/// What the shelf shows about iCloud saves: each game's state, the last
/// device that saved it, and a short message after a sync that moved
/// something ("Save sincronizado"). Shared by the iPhone and Mac apps.
@MainActor
@Observable
final class SyncStatus {
    static let shared = SyncStatus()

    enum State: Equatable {
        /// In step with iCloud.
        case upToDate
        /// Going up now.
        case sending
        /// A newer save from another device is still coming down.
        case incoming
        /// Changed on two devices; the newest stayed.
        case conflict
    }

    private(set) var games: [String: SaveSync.GameReport] = [:]
    private(set) var syncing = false
    private(set) var lastSync: Date?
    /// The message of the moment, shown for a few seconds.
    private(set) var toast: String?

    private init() {}

    func state(for id: String) -> State? {
        guard SaveSync.isEnabled, let report = games[id] else { return nil }
        if syncing, report.uploaded > 0 { return .sending }
        if report.waiting > 0 { return .incoming }
        if report.conflict { return .conflict }
        return .upToDate
    }

    /// "Último save: MacBook de Ana, há 3 minutos".
    func lastSave(for id: String) -> String? {
        guard let report = games[id], let device = report.lastDevice, let date = report.lastDate else { return nil }
        return String(localized: "Último save: \(device), \(date.formatted(.relative(presentation: .named)))")
    }

    func began() {
        syncing = true
    }

    /// Takes a sync's report; tells the player when a save arrived from
    /// another device, and when this one's went up if `announceUploads`
    /// (after a game, not the routine sync at launch).
    func finished(_ report: SaveSync.Report, titles: [String: String], announceUploads: Bool = false) {
        syncing = false
        lastSync = Date()
        for (id, game) in report.games {
            // Keep "who saved last" when this run could not read it.
            var merged = game
            if merged.lastDevice == nil { merged.lastDevice = games[id]?.lastDevice; merged.lastDate = games[id]?.lastDate }
            games[id] = merged
        }
        let arrived = report.games.filter { $0.value.downloaded > 0 }
        let sent = report.games.filter { $0.value.uploaded > 0 }
        if let (id, game) = arrived.first {
            let title = titles[id] ?? id
            show(game.lastDevice.map { String(localized: "Save de \($0) chegou: \(title)") }
                 ?? String(localized: "Save sincronizado: \(title)"))
        } else if announceUploads, let (id, _) = sent.first {
            show(sent.count == 1
                 ? String(localized: "Save sincronizado: \(titles[id] ?? id)")
                 : String(localized: "\(sent.count) saves sincronizados"))
        }
    }

    func show(_ message: String) {
        toast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if toast == message { toast = nil }
        }
    }
}

extension SaveSync.GameFolders {
    /// Where a game's saves live on this device.
    init(_ game: GameEntry) {
        self.init(id: game.id, title: game.title, folder: game.folder,
                  userData: GameStorage.userDataFolder(for: game),
                  states: StateStore.folder(for: game.id))
    }
}

extension SyncStatus {
    /// Before a game opens: a newer save from another device still on its
    /// way? Waits for it up to `limit` seconds, syncing meanwhile.
    nonisolated static func waitForIncoming(_ game: GameEntry, limit: TimeInterval = 20) async -> Bool {
        let folders = SaveSync.GameFolders(game)
        let start = Date()
        while SaveSync.hasIncoming(folders) {
            guard Date().timeIntervalSince(start) < limit else { return false }
            _ = SaveSync.sync([folders])
            try? await Task.sleep(for: .seconds(1.5))
        }
        return true
    }
}
