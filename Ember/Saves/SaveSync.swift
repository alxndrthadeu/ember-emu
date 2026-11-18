import Foundation

/// Saves and save states kept in iCloud Drive, on every iPhone with the
/// same game (same folder name, which comes from the
/// game's title). Only saves: games never go to iCloud this way.
///
/// iCloud Drive/Ember/Saves/<game id>/
///   folder/…     saves in the game folder (Save1.rxdata, Save Data/…)
///   userdata/…   saves in UserData/<id> (Essentials' Game.rxdata)
///   states/…     Ember's save states and their pictures
///
/// Each run compares every file with what it was at the last sync:
/// changed here → up; changed in iCloud → down (the copy it replaces
/// goes to Backups); changed on both sides → the newer one wins and the
/// other goes to Backups as a conflict. Nothing is ever deleted on
/// either side. Runs off the main thread. While a game plays, only
/// `upload` runs: what the game just saved goes up, and nothing comes
/// down under the running game.
enum SaveSync {
    static let enabledKey = "settings.iCloudSaves"

    /// Automatic sync, for every game (Settings). Sending and bringing a
    /// game's saves by hand works either way.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Games left out of the automatic sync (each game's iCloud screen).
    static let manualGamesKey = "saves.manualSync"

    /// Whether this game's saves sync on their own: automatic sync on,
    /// and the game not set to "only by hand".
    static func syncsAutomatically(_ id: String) -> Bool {
        isEnabled && !(UserDefaults.standard.stringArray(forKey: manualGamesKey) ?? []).contains(id)
    }

    static func setSyncsAutomatically(_ on: Bool, for id: String) {
        var manual = Set(UserDefaults.standard.stringArray(forKey: manualGamesKey) ?? [])
        if on { manual.remove(id) } else { manual.insert(id) }
        UserDefaults.standard.set(manual.sorted(), forKey: manualGamesKey)
    }

    struct Report: Equatable {
        var uploaded = 0
        var downloaded = 0
        var conflicts: [String] = []
        /// Files iCloud still has to bring down; a later run gets them.
        var waiting = 0
        /// Per game id.
        var games: [String: GameReport] = [:]
    }

    /// What one sync did for one game, and who saved it last.
    struct GameReport: Equatable, Sendable {
        var uploaded = 0
        var downloaded = 0
        var waiting = 0
        var conflict = false
        /// The device whose saves iCloud holds now, and when.
        var lastDevice: String?
        var lastDate: Date?
    }

    /// This device's name for "last saved on" ("iPhone de Ana", the Mac's
    /// name). Set by the app at launch.
    nonisolated(unsafe) static var deviceName = "Ember"

    /// One game to sync: its id and the folders its saves live in.
    struct GameFolders: Sendable {
        let id: String
        let title: String
        let folder: URL
        let userData: URL
        let states: URL
    }

    /// iCloud's folder, once it answered: asking again is free, but the
    /// first ask in a process can take long while iCloud gets the
    /// container ready (a Mac just signed in, the app just installed).
    nonisolated(unsafe) private static var knownRoot: URL?
    private static let rootLock = NSLock()

    /// Asks for iCloud's folder ahead of the first save (as a game opens),
    /// so sending it does not wait. Off the main thread.
    static func prepare() {
        DispatchQueue.global(qos: .utility).async { _ = cloudRoot() }
    }

    static func cloudRoot() -> URL? {
        rootLock.lock()
        let known = knownRoot
        rootLock.unlock()
        if let known { return known }
        let root = findCloudRoot()
        if let root {
            rootLock.lock()
            knownRoot = root
            rootLock.unlock()
        }
        return root
    }

    private static func findCloudRoot() -> URL? {
        #if DEBUG
        if GameArchive.fakeCloud {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let folder = support.appendingPathComponent("FakeCloud/Saves", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        #endif
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: GameArchive.containerID)
        else { return nil }
        let folder = container.appendingPathComponent("Documents/Saves", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    // MARK: - Sync

    /// The automatic sync: the games that sync on their own.
    static func sync(_ games: [GameFolders]) -> Report {
        let games = games.filter { syncsAutomatically($0.id) }
        guard !games.isEmpty, let root = cloudRoot() else { return Report() }
        return sync(games, root: root)
    }

    /// Against any folder standing in for iCloud (tests).
    static func sync(_ games: [GameFolders], root: URL, uploadOnly: Bool = false) -> Report {
        var report = Report()
        for game in games {
            sync(game, cloud: root.appendingPathComponent(game.id, isDirectory: true),
                 uploadOnly: uploadOnly, report: &report)
        }
        return report
    }

    /// While the game plays: sends what changed on this device (a save
    /// the game just wrote, a save state) and brings nothing down, so no
    /// file changes under the running game. What iCloud has newer waits
    /// for the next full sync.
    static func upload(_ game: GameFolders) -> Report {
        guard syncsAutomatically(game.id), let root = cloudRoot() else { return Report() }
        return sync([game], root: root, uploadOnly: true)
    }

    /// Whether this device has saves of the game that iCloud has not got
    /// yet (a send that could not happen: iCloud not ready, no network).
    static func hasOutgoing(_ game: GameFolders) -> Bool {
        let state = SyncState.load(game.id)
        for area in areas(of: game) {
            for name in area.files {
                let date = modified(area.local.appendingPathComponent(name))
                if date != nil, date != state.files["\(area.name)/\(name)"]?.local { return true }
            }
        }
        return false
    }

    private static func sync(_ game: GameFolders, cloud: URL, uploadOnly: Bool, report: inout Report) {
        let before = report
        var state = SyncState.load(game.id)
        for area in areas(of: game) {
            let cloudArea = cloud.appendingPathComponent(area.name, isDirectory: true)
            var names = Set(area.files)
            for name in allFiles(in: cloudArea, includingPlaceholders: true) { names.insert(name) }
            for name in names.sorted() {
                let key = "\(area.name)/\(name)"
                let local = area.local.appendingPathComponent(name)
                let remote = cloudArea.appendingPathComponent(name)
                syncFile(key: key, local: local, remote: remote, game: game, uploadOnly: uploadOnly,
                         state: &state, report: &report)
            }
        }
        state.save(game.id)

        var mine = GameReport(uploaded: report.uploaded - before.uploaded,
                              downloaded: report.downloaded - before.downloaded,
                              waiting: report.waiting - before.waiting,
                              conflict: report.conflicts.count > before.conflicts.count)
        // Who saved last travels with the saves.
        let last = cloud.appendingPathComponent("last.json")
        if mine.uploaded > 0, let data = try? JSONEncoder().encode(LastSave(device: deviceName, date: Date())) {
            try? data.write(to: last, options: .atomic)
        }
        if let data = try? Data(contentsOf: last), let saved = try? JSONDecoder().decode(LastSave.self, from: data) {
            mine.lastDevice = saved.device
            mine.lastDate = saved.date
        } else if fileExistsOrPlaceholder(last) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: last)
        }
        report.games[game.id] = mine
    }

    /// The three places a game's saves live, with the files in each.
    private static func areas(of game: GameFolders) -> [(name: String, local: URL, files: [String])] {
        [
            ("folder", game.folder, folderSaves(in: game.folder)),
            ("userdata", game.userData, allFiles(in: game.userData).filter(isUserDataSave)),
            ("states", game.states, allFiles(in: game.states).filter(isStateFile)),
        ]
    }

    private struct LastSave: Codable {
        let device: String
        let date: Date
    }

    private static func fileExistsOrPlaceholder(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || FileManager.default.fileExists(atPath: placeholder(for: url).path)
    }

    /// Whether iCloud has saves of this game newer than this device's,
    /// still to come down (asked before a game opens).
    static func hasIncoming(_ game: GameFolders) -> Bool {
        guard syncsAutomatically(game.id), let root = cloudRoot() else { return false }
        return hasIncoming(game, root: root)
    }

    /// Against any folder standing in for iCloud (tests).
    static func hasIncoming(_ game: GameFolders, root: URL) -> Bool {
        let cloud = root.appendingPathComponent(game.id, isDirectory: true)
        let state = SyncState.load(game.id)
        for area in ["folder", "userdata", "states"] {
            let cloudArea = cloud.appendingPathComponent(area, isDirectory: true)
            for name in allFiles(in: cloudArea, includingPlaceholders: true) {
                let remote = cloudArea.appendingPathComponent(name)
                let key = "\(area)/\(name)"
                if !FileManager.default.fileExists(atPath: remote.path) {
                    // Only a placeholder: new to this device unless synced
                    // before (iCloud also evicts old files to save space).
                    if state.files[key] == nil { return true }
                    continue
                }
                if let date = modified(remote), date != state.files[key]?.remote { return true }
            }
        }
        return false
    }

    private static func syncFile(key: String, local: URL, remote: URL, game: GameFolders, uploadOnly: Bool = false,
                                 state: inout SyncState, report: inout Report) {
        let fm = FileManager.default
        let localDate = modified(local)
        // A file iCloud knows but has not brought down yet.
        if !fm.fileExists(atPath: remote.path), fm.fileExists(atPath: placeholder(for: remote).path) {
            if uploadOnly { return }
            try? fm.startDownloadingUbiquitousItem(at: remote)
            report.waiting += 1
            return
        }
        let remoteDate = modified(remote)
        let last = state.files[key]
        let localChanged = localDate != nil && localDate != last?.local
        let remoteChanged = remoteDate != nil && remoteDate != last?.remote
        // Uploading only: anything that would come down is left as it is
        // (and unrecorded) for the next full sync.
        if uploadOnly, remoteChanged,
           !localChanged || (localDate ?? .distantPast) < (remoteDate ?? .distantPast) { return }

        do {
            switch (localChanged, remoteChanged) {
            case (false, false):
                return
            case (true, false):
                try copy(local, to: remote)
                report.uploaded += 1
            case (false, true):
                if localDate != nil { try keep(local, of: game, reason: "iCloud") }
                try copy(remote, to: local)
                report.downloaded += 1
            case (true, true):
                if sameContents(local, remote) { break }
                // The newer one plays on; the other is kept.
                if (localDate ?? .distantPast) >= (remoteDate ?? .distantPast) {
                    try keep(remote, of: game, reason: "conflito iCloud", name: key)
                    try copy(local, to: remote)
                    report.uploaded += 1
                } else {
                    try keep(local, of: game, reason: "conflito iCloud")
                    try copy(remote, to: local)
                    report.downloaded += 1
                }
                report.conflicts.append(game.title)
            }
            state.files[key] = SyncState.File(local: modified(local), remote: modified(remote))
        } catch {
            // Tried again next time.
        }
    }

    // MARK: - Files

    /// RPG Maker saves at the top of the game folder, and everything in
    /// its "Save Data" folder.
    private static func folderSaves(in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var saves = names.filter(SaveManager.isGameFolderSaveName)
        if let saveData = names.first(where: { $0.caseInsensitiveCompare("Save Data") == .orderedSame }) {
            saves += allFiles(in: folder.appendingPathComponent(saveData)).map { "\(saveData)/\($0)" }
        }
        return saves
    }

    private static func isUserDataSave(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        return !["systemout.txt", "errorlog.txt", "cover.jpg", ".ds_store"].contains(name) && !name.hasPrefix(".")
    }

    private static func isStateFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return ["state", "jpg", "png"].contains(ext) && !path.contains("/")
    }

    /// Paths under a folder, relative to it. iCloud placeholders
    /// (".name.icloud") are listed by their real name when asked.
    private static func allFiles(in folder: URL, includingPlaceholders: Bool = false) -> [String] {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var result: [String] = []
        let base = folder.standardizedFileURL.path
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            var relative = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            var name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                guard includingPlaceholders else { continue }
                name = String(name.dropFirst().dropLast(".icloud".count))
                relative = ((relative as NSString).deletingLastPathComponent as NSString).appendingPathComponent(name)
            } else if name.hasPrefix(".") {
                continue
            }
            result.append(relative)
        }
        return result
    }

    private static func placeholder(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
    }

    private static func modified(_ url: URL) -> Date? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var url = url
        url.removeAllCachedResourceValues()
        return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private static func sameContents(_ a: URL, _ b: URL) -> Bool {
        FileManager.default.contentsEqual(atPath: a.path, andPath: b.path)
    }

    /// Copies through a file coordinator (iCloud may be using the file)
    /// and keeps the modification date, so both sides compare equal.
    private static func copy(_ source: URL, to target: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], writingItemAt: target,
                                       options: .forReplacing, error: &coordinatorError) { from, to in
            do {
                let temp = to.deletingLastPathComponent().appendingPathComponent(".sync-\(UUID().uuidString)")
                try fm.copyItem(at: from, to: temp)
                if fm.fileExists(atPath: to.path) {
                    _ = try fm.replaceItemAt(to, withItemAt: temp)
                } else {
                    try fm.moveItem(at: temp, to: to)
                }
                if let date = modified(from) {
                    try fm.setAttributes([.modificationDate: date], ofItemAtPath: to.path)
                }
            } catch {
                copyError = error
            }
        }
        if let error = coordinatorError ?? copyError { throw error }
    }

    /// A copy in Documents/Backups/<game>/<reason> <date>/ before it is
    /// replaced.
    private static func keep(_ url: URL, of game: GameFolders, reason: String, name: String? = nil) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let target = documents
            .appendingPathComponent("Backups/\(game.id)/\(reason) \(formatter.string(from: Date()))")
            .appendingPathComponent(name ?? url.lastPathComponent)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.copyItem(at: url, to: target)
        }
    }
}

// MARK: - By hand (each game's iCloud screen)

extension SaveSync {
    /// One side of a game's saves: this device or iCloud.
    struct Side: Equatable, Sendable {
        var files = 0
        /// Files iCloud has not brought down yet (their size is unknown).
        var waiting = 0
        var bytes: Int64 = 0
        /// The newest save on this side.
        var latest: Date?
        /// Who sent them (iCloud only).
        var device: String?
        var isEmpty: Bool { files + waiting == 0 }
    }

    /// What this device has of a game's saves.
    static func localSide(_ game: GameFolders) -> Side {
        var side = Side()
        for area in areas(of: game) {
            for name in area.files {
                let url = area.local.appendingPathComponent(name)
                side.files += 1
                side.bytes += size(of: url)
                if let date = modified(url), date > (side.latest ?? .distantPast) { side.latest = date }
            }
        }
        return side
    }

    /// What iCloud has of a game's saves; nil without iCloud.
    static func cloudSide(_ game: GameFolders) -> Side? {
        guard let root = cloudRoot() else { return nil }
        return cloudSide(game, root: root)
    }

    static func cloudSide(_ game: GameFolders, root: URL) -> Side {
        let cloud = root.appendingPathComponent(game.id, isDirectory: true)
        var side = Side()
        for area in ["folder", "userdata", "states"] {
            let folder = cloud.appendingPathComponent(area, isDirectory: true)
            for name in allFiles(in: folder, includingPlaceholders: true) {
                let url = folder.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    side.waiting += 1
                    continue
                }
                side.files += 1
                side.bytes += size(of: url)
                if let date = modified(url), date > (side.latest ?? .distantPast) { side.latest = date }
            }
        }
        let last = cloud.appendingPathComponent("last.json")
        if let data = try? Data(contentsOf: last), let saved = try? JSONDecoder().decode(LastSave.self, from: data) {
            side.device = saved.device
            if side.latest == nil || side.waiting > 0 { side.latest = max(side.latest ?? .distantPast, saved.date) }
        } else if fileExistsOrPlaceholder(last) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: last)
        }
        return side
    }

    enum ManualError: LocalizedError {
        case noCloud
        case nothingHere
        case nothingThere

        var errorDescription: String? {
            switch self {
            case .noCloud: String(localized: "O iCloud não está disponível. Confira se você entrou na sua conta e se o iCloud Drive está ligado.")
            case .nothingHere: String(localized: "Não há saves deste jogo neste aparelho.")
            case .nothingThere: String(localized: "Não há saves deste jogo no iCloud.")
            }
        }
    }

    /// Sends every save of this game, replacing iCloud's copy of each.
    /// What iCloud had is kept in Backups first. Returns the files sent.
    @discardableResult
    static func sendAll(_ game: GameFolders) throws -> Int {
        guard let root = cloudRoot() else { throw ManualError.noCloud }
        return try sendAll(game, root: root)
    }

    @discardableResult
    static func sendAll(_ game: GameFolders, root: URL) throws -> Int {
        let cloud = root.appendingPathComponent(game.id, isDirectory: true)
        var state = SyncState.load(game.id)
        var sent = 0
        for area in areas(of: game) {
            for name in area.files {
                let key = "\(area.name)/\(name)"
                let local = area.local.appendingPathComponent(name)
                let remote = cloud.appendingPathComponent(key)
                if FileManager.default.fileExists(atPath: remote.path) {
                    if sameContents(local, remote) {
                        state.files[key] = SyncState.File(local: modified(local), remote: modified(remote))
                        continue
                    }
                    try keep(remote, of: game, reason: "iCloud substituído", name: key)
                }
                try copy(local, to: remote)
                state.files[key] = SyncState.File(local: modified(local), remote: modified(remote))
                sent += 1
            }
        }
        guard sent > 0 || !state.files.isEmpty else { throw ManualError.nothingHere }
        state.save(game.id)
        if let data = try? JSONEncoder().encode(LastSave(device: deviceName, date: Date())) {
            try? data.write(to: cloud.appendingPathComponent("last.json"), options: .atomic)
        }
        return sent
    }

    /// Brings every save of this game from iCloud, replacing this device's
    /// copy of each (kept in Backups first). Files iCloud has not brought
    /// down yet are asked for and counted in `waiting`: call again.
    static func bringAll(_ game: GameFolders) throws -> (brought: Int, waiting: Int) {
        guard let root = cloudRoot() else { throw ManualError.noCloud }
        return try bringAll(game, root: root)
    }

    static func bringAll(_ game: GameFolders, root: URL) throws -> (brought: Int, waiting: Int) {
        let cloud = root.appendingPathComponent(game.id, isDirectory: true)
        var state = SyncState.load(game.id)
        var brought = 0
        var waiting = 0
        var found = 0
        let locals: [String: URL] = ["folder": game.folder, "userdata": game.userData, "states": game.states]
        for area in ["folder", "userdata", "states"] {
            let folder = cloud.appendingPathComponent(area, isDirectory: true)
            for name in allFiles(in: folder, includingPlaceholders: true) {
                found += 1
                let key = "\(area)/\(name)"
                let remote = folder.appendingPathComponent(name)
                let local = locals[area]!.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: remote.path) else {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: remote)
                    waiting += 1
                    continue
                }
                if FileManager.default.fileExists(atPath: local.path) {
                    if sameContents(local, remote) {
                        state.files[key] = SyncState.File(local: modified(local), remote: modified(remote))
                        continue
                    }
                    try keep(local, of: game, reason: "antes do iCloud")
                }
                try copy(remote, to: local)
                state.files[key] = SyncState.File(local: modified(local), remote: modified(remote))
                brought += 1
            }
        }
        guard found > 0 else { throw ManualError.nothingThere }
        state.save(game.id)
        return (brought, waiting)
    }

    private static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }
}

// MARK: - A game playing in another instance (Mac)

extension SaveSync {
    /// The Mac runs each game in its own instance: the library must not
    /// bring saves down under one. The instance marks its game while it
    /// runs (with its process id, so a crash does not leave it marked).
    private static func playingMarker(_ id: String) -> URL {
        let safe = id.replacingOccurrences(of: "/", with: "_")
        return FileManager.default.temporaryDirectory.appendingPathComponent("ember-playing-\(safe)")
    }

    static func markPlaying(_ id: String, _ on: Bool) {
        let marker = playingMarker(id)
        if on {
            try? String(ProcessInfo.processInfo.processIdentifier).write(to: marker, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: marker)
        }
    }

    static func isPlayingElsewhere(_ id: String) -> Bool {
        guard let text = try? String(contentsOf: playingMarker(id), encoding: .utf8),
              let pid = Int32(text), pid != ProcessInfo.processInfo.processIdentifier else { return false }
        return kill(pid, 0) == 0
    }
}

/// What each file was at the last sync, per game, on this device.
private struct SyncState: Codable {
    struct File: Codable, Equatable {
        var local: Date?
        var remote: Date?
    }

    var files: [String: File] = [:]

    private static func url(_ id: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("SaveSync/\(id).json")
    }

    static func load(_ id: String) -> SyncState {
        guard let data = try? Data(contentsOf: url(id)) else { return SyncState() }
        return (try? JSONDecoder().decode(SyncState.self, from: data)) ?? SyncState()
    }

    func save(_ id: String) {
        let url = Self.url(id)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
