import AppleArchive
import Foundation
import System

/// "Arquivar no iCloud": a game leaves the iPhone for the player's
/// iCloud Drive (an "Ember" folder in the Files app) and comes back
/// with a tap, like iOS offloading an app but keeping its data.
///
/// What leaves: the game folder, packed with Apple Archive (LZFSE:
/// fast, about 14% smaller for RPG Maker games, whose music and art are
/// already compressed). What stays: the cover, the name, the Essentials
/// saves (UserData), the save states and the history. Once iCloud has
/// the file, Ember asks iOS to drop the local copy, and the space is
/// back.
struct ArchivedGame: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let originalTitle: String
    /// File name inside the iCloud container's Documents folder.
    let archiveName: String
    /// The game folder's size before packing.
    let size: Int64
    let archived: Date
}

enum GameArchive {
    static let containerID = "iCloud.com.alexandrethadeu.ember"

    #if DEBUG
    static let fakeCloud = ProcessInfo.processInfo.environment["EMBER_FAKE_CLOUD"] != nil
    #else
    static let fakeCloud = false
    #endif

    enum ArchiveError: LocalizedError {
        case noICloud
        case packFailed
        case notFound(String)

        var errorDescription: String? {
            switch self {
            case .noICloud:
                String(localized: "O iCloud não está disponível. Entre na sua conta em Ajustes do iPhone e ligue o iCloud Drive.")
            case .packFailed:
                String(localized: "Não deu para compactar o jogo. Confira se há espaço livre e tente de novo.")
            case .notFound(let title):
                String(localized: "O arquivo de “\(title)” não está mais no iCloud Drive.")
            }
        }
    }

    /// Records of archived games, kept on the iPhone.
    private static var recordsFolder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Archived", isDirectory: true)
    }

    /// The iCloud folder, or nil without iCloud. Call off the main
    /// thread: the first call may set the container up.
    static func cloudFolder() -> URL? {
        #if DEBUG
        // Development aid: EMBER_FAKE_CLOUD=1 uses a local folder, so the
        // simulator (no iCloud account) can run the whole round trip.
        if fakeCloud {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let folder = support.appendingPathComponent("FakeCloud", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        #endif
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else { return nil }
        let folder = container.appendingPathComponent("Documents/Jogos arquivados", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func records() -> [ArchivedGame] {
        let folder = recordsFolder
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return names.filter { $0.hasSuffix(".json") }
            .compactMap { try? decoder.decode(ArchivedGame.self, from: Data(contentsOf: folder.appendingPathComponent($0))) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private static func save(_ record: ArchivedGame) throws {
        try FileManager.default.createDirectory(at: recordsFolder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: recordsFolder.appendingPathComponent("\(record.id).json"))
    }

    private static func dropRecord(_ id: String) {
        try? FileManager.default.removeItem(at: recordsFolder.appendingPathComponent("\(id).json"))
    }

    // MARK: - Archiving

    /// Packs the game, moves the pack to iCloud and removes the game
    /// folder. Runs off the main thread.
    static func archive(_ game: GameEntry) throws -> ArchivedGame {
        guard let cloud = cloudFolder() else { throw ArchiveError.noICloud }
        let fm = FileManager.default
        let size = EmberBackup.size(of: game.folder)
        let name = "\(game.id).emberarchive"
        let packed = fm.temporaryDirectory.appendingPathComponent(name)
        try? fm.removeItem(at: packed)
        try pack(game.folder, into: packed)

        let target = cloud.appendingPathComponent(name)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        // Moves the file into iCloud; iOS uploads it from there.
        if fakeCloud {
            try fm.moveItem(at: packed, to: target)
        } else {
            try fm.setUbiquitous(true, itemAt: packed, destinationURL: target)
        }

        // The test stand-in is instant: slow it down so the animation shows.
        if fakeCloud { Thread.sleep(forTimeInterval: 3) }
        let record = ArchivedGame(id: game.id, title: game.title, originalTitle: game.originalTitle,
                                  archiveName: name, size: size, archived: Date())
        try save(record)
        try fm.removeItem(at: game.folder)
        return record
    }

    /// Whether iCloud has the whole pack (always true for the stand-in).
    static func isUploaded(_ record: ArchivedGame) -> Bool {
        if fakeCloud { return true }
        guard let cloud = cloudFolder() else { return false }
        var url = cloud.appendingPathComponent(record.archiveName)
        url.removeAllCachedResourceValues()
        return (try? url.resourceValues(forKeys: [.ubiquitousItemIsUploadedKey]))?.ubiquitousItemIsUploaded == true
            || !FileManager.default.fileExists(atPath: url.path)
    }

    /// Frees the local copies of packs iCloud already has. Called after
    /// archiving and whenever the library shows up.
    static func evictUploaded() {
        guard let cloud = cloudFolder() else { return }
        let fm = FileManager.default
        for record in records() {
            let url = cloud.appendingPathComponent(record.archiveName)
            let keys: Set<URLResourceKey> = [.ubiquitousItemIsUploadedKey, .ubiquitousItemDownloadingStatusKey]
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.ubiquitousItemIsUploaded == true,
                  values.ubiquitousItemDownloadingStatus == .current
            else { continue }
            try? fm.evictUbiquitousItem(at: url)
        }
    }

    // MARK: - Bringing back

    /// Downloads the pack if needed (calling `progress` with a status
    /// line), unpacks it into the library and forgets the archive.
    static func restore(_ record: ArchivedGame, progress: @escaping (String, Double?) -> Void) async throws {
        guard let cloud = cloudFolder() else { throw ArchiveError.noICloud }
        let fm = FileManager.default
        let url = cloud.appendingPathComponent(record.archiveName)
        guard fm.fileExists(atPath: url.path) || isPlaceholderPresent(url) else {
            throw ArchiveError.notFound(record.title)
        }

        // Download from iCloud, when only the placeholder is here.
        if !fakeCloud, !isDownloaded(url) {
            try fm.startDownloadingUbiquitousItem(at: url)
            while !isDownloaded(url) {
                let percent = await MainActor.run { CloudProgress.shared.items[record.archiveName]?.downloaded }
                progress(String(localized: "Baixando do iCloud…"), percent.map { $0 / 100 })
                // At 100%, iCloud may still be finishing the file: the
                // coordinated read below waits for it, so stop polling.
                if let percent, percent >= 100 { break }
                try await Task.sleep(for: .milliseconds(400))
            }
        }

        progress(String(localized: "Descompactando…"), nil)
        let target = GameImporter.gamesFolder.appendingPathComponent(record.id, isDirectory: true)
        let scratch = fm.temporaryDirectory.appendingPathComponent("Unarchive-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }
        // A coordinated read hands over the whole file, downloading what
        // is still missing.
        var coordinatorError: NSError?
        var unpackError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readable in
            do { try unpack(readable, into: scratch) } catch { unpackError = error }
        }
        if let error = coordinatorError ?? unpackError { throw error }
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.createDirectory(at: GameImporter.gamesFolder, withIntermediateDirectories: true)
        try fm.moveItem(at: scratch, to: target)

        // The game is home: the pack leaves iCloud (no space used twice)
        // and the record goes.
        removeFromCloud(url)
        dropRecord(record.id)
    }

    /// Deletes a pack from iCloud Drive, also when only its evicted
    /// placeholder (".name.icloud") is on the iPhone.
    private static func removeFromCloud(_ url: URL) {
        let fm = FileManager.default
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinatorError) { writable in
            try? fm.removeItem(at: writable)
        }
        let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
        if fm.fileExists(atPath: placeholder.path) {
            NSFileCoordinator().coordinate(writingItemAt: placeholder, options: .forDeleting, error: &coordinatorError) { writable in
                try? fm.removeItem(at: writable)
            }
        }
        if fm.fileExists(atPath: url.path) { try? fm.removeItem(at: url) }
    }

    /// Deletes an archived game for good (the pack and its record).
    static func delete(_ record: ArchivedGame) {
        if let cloud = cloudFolder() {
            removeFromCloud(cloud.appendingPathComponent(record.archiveName))
        }
        dropRecord(record.id)
    }

    /// Whether the pack is on the iPhone. Resource values are cached per
    /// URL, so each check reads them fresh (with the cache, a finished
    /// download kept looking unfinished).
    private static func isDownloaded(_ url: URL) -> Bool {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        let status = (try? fresh.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?
            .ubiquitousItemDownloadingStatus
        return status == .current || status == .downloaded
    }

    /// An evicted iCloud file shows as a ".name.icloud" placeholder.
    private static func isPlaceholderPresent(_ url: URL) -> Bool {
        let placeholder = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).icloud")
        return FileManager.default.fileExists(atPath: placeholder.path)
            || (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
    }

    // MARK: - Apple Archive

    private static func pack(_ folder: URL, into file: URL) throws {
        guard let out = ArchiveByteStream.fileStream(path: FilePath(file.path), mode: .writeOnly,
                                                     options: [.create, .truncate],
                                                     permissions: FilePermissions(rawValue: 0o644)),
              let compress = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: out),
              let encode = ArchiveStream.encodeStream(writingTo: compress),
              let keys = ArchiveHeader.FieldKeySet("TYP,PAT,LNK,DAT,MOD,MTM")
        else { throw ArchiveError.packFailed }
        defer {
            try? encode.close()
            try? compress.close()
            try? out.close()
        }
        do {
            try encode.writeDirectoryContents(archiveFrom: FilePath(folder.path), keySet: keys)
        } catch {
            throw ArchiveError.packFailed
        }
    }

    private static func unpack(_ file: URL, into folder: URL) throws {
        guard let input = ArchiveByteStream.fileStream(path: FilePath(file.path), mode: .readOnly,
                                                       options: [], permissions: FilePermissions(rawValue: 0o644)),
              let decompress = ArchiveByteStream.decompressionStream(readingFrom: input),
              let decode = ArchiveStream.decodeStream(readingFrom: decompress),
              let extract = ArchiveStream.extractStream(extractingTo: FilePath(folder.path),
                                                        flags: [.ignoreOperationNotPermitted])
        else { throw ArchiveError.packFailed }
        defer {
            try? extract.close()
            try? decode.close()
            try? decompress.close()
            try? input.close()
        }
        _ = try ArchiveStream.process(readingFrom: decode, writingTo: extract)
    }
}

/// Upload and download percentages of Ember's packs in iCloud, from
/// the system's metadata query (URL resource values have no percent).
@MainActor
final class CloudProgress: ObservableObject {
    static let shared = CloudProgress()

    struct Item: Equatable {
        var uploaded: Double?
        var downloaded: Double?
        var isUploaded = false
    }

    /// By file name.
    @Published private(set) var items: [String: Item] = [:]
    private let query = NSMetadataQuery()

    private init() {
        guard !GameArchive.fakeCloud else { return }
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.emberarchive'", NSMetadataItemFSNameKey)
        for name in [NSNotification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { _ in
                MainActor.assumeIsolated { CloudProgress.shared.refresh() }
            }
        }
        query.start()
    }

    private func refresh() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        var next: [String: Item] = [:]
        for case let entry as NSMetadataItem in query.results {
            guard let name = entry.value(forAttribute: NSMetadataItemFSNameKey) as? String else { continue }
            next[name] = Item(
                uploaded: entry.value(forAttribute: NSMetadataUbiquitousItemPercentUploadedKey) as? Double,
                downloaded: entry.value(forAttribute: NSMetadataUbiquitousItemPercentDownloadedKey) as? Double,
                isUploaded: entry.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool ?? false)
        }
        items = next
    }
}
