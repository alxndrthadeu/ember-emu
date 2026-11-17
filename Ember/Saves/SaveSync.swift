import Foundation

/// Saves and save states kept in iCloud Drive, on every iPhone, iPad
/// or Mac with the same game (same folder name, which comes from the
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
/// either side. Runs off the main thread, never while a game plays.
enum SaveSync {
    static let enabledKey = "settings.iCloudSaves"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    struct Report: Equatable {
        var uploaded = 0
        var downloaded = 0
        var conflicts: [String] = []
        /// Files iCloud still has to bring down; a later run gets them.
        var waiting = 0
    }

    /// One game to sync: its id and the folders its saves live in.
    struct GameFolders: Sendable {
        let id: String
        let title: String
        let folder: URL
        let userData: URL
        let states: URL
    }

    static func cloudRoot() -> URL? {
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

    static func sync(_ games: [GameFolders]) -> Report {
        guard isEnabled, let root = cloudRoot() else { return Report() }
        return sync(games, root: root)
    }

    /// Against any folder standing in for iCloud (tests).
    static func sync(_ games: [GameFolders], root: URL) -> Report {
        var report = Report()
        for game in games {
            sync(game, cloud: root.appendingPathComponent(game.id, isDirectory: true), report: &report)
        }
        return report
    }

    private static func sync(_ game: GameFolders, cloud: URL, report: inout Report) {
        var state = SyncState.load(game.id)
        let areas: [(name: String, local: URL, files: [String])] = [
            ("folder", game.folder, folderSaves(in: game.folder)),
            ("userdata", game.userData, allFiles(in: game.userData).filter(isUserDataSave)),
            ("states", game.states, allFiles(in: game.states).filter(isStateFile)),
        ]
        for area in areas {
            let cloudArea = cloud.appendingPathComponent(area.name, isDirectory: true)
            var names = Set(area.files)
            for name in allFiles(in: cloudArea, includingPlaceholders: true) { names.insert(name) }
            for name in names.sorted() {
                let key = "\(area.name)/\(name)"
                let local = area.local.appendingPathComponent(name)
                let remote = cloudArea.appendingPathComponent(name)
                syncFile(key: key, local: local, remote: remote, game: game, state: &state, report: &report)
            }
        }
        state.save(game.id)
    }

    private static func syncFile(key: String, local: URL, remote: URL, game: GameFolders,
                                 state: inout SyncState, report: inout Report) {
        let fm = FileManager.default
        let localDate = modified(local)
        // A file iCloud knows but has not brought down yet.
        if !fm.fileExists(atPath: remote.path), fm.fileExists(atPath: placeholder(for: remote).path) {
            try? fm.startDownloadingUbiquitousItem(at: remote)
            report.waiting += 1
            return
        }
        let remoteDate = modified(remote)
        let last = state.files[key]
        let localChanged = localDate != nil && localDate != last?.local
        let remoteChanged = remoteDate != nil && remoteDate != last?.remote

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
