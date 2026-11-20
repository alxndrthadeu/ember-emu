import AppKit
import Network

/// The Mac library's side of "Enviar jogos para o Mac": advertises this
/// Mac nearby, asks before taking anything, then receives each game
/// file by file and puts it in the library under the iPhone's game id.
///
/// A game already here keeps its files; its saves and states come in
/// only where the iPhone's are newer (the Mac's go to Backups first).
@MainActor
@Observable
final class MacTransferServer {
    static let shared = MacTransferServer()

    /// What is coming in now, for the library: a title and 0…1.
    private(set) var receiving: (title: String, fraction: Double)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "ember.transfer-server", qos: .userInitiated)

    private init() {}

    func start() {
        guard listener == nil, let listener = try? NWListener(using: TransferProtocol.parameters) else { return }
        listener.service = NWListener.Service(name: Host.current().localizedName ?? "Mac",
                                              type: TransferProtocol.serviceType)
        listener.newConnectionHandler = { connection in
            Task { @MainActor in MacTransferServer.shared.accept(connection) }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    // MARK: - One iPhone sending

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        TransferProtocol.receiveOne(on: connection) { kind, data in
            guard kind == .offer, let offer = try? JSONDecoder().decode(TransferProtocol.Offer.self, from: data) else {
                connection.cancel()
                return
            }
            Task { @MainActor in MacTransferServer.shared.ask(offer, on: connection) }
        }
    }

    private func ask(_ offer: TransferProtocol.Offer, on connection: NWConnection) {
        let games = offer.games.filter { TransferProtocol.safeID($0.id) }
        let total = games.reduce(0) { $0 + $1.bytes }
        let alert = NSAlert()
        alert.messageText = String(localized: "\(offer.device) quer enviar jogos para este Mac")
        let list = games.map { "• \($0.title) (\(ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file)))" }
            .joined(separator: "\n")
        alert.informativeText = list + "\n\n" + String(localized: "Total: \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)). Os saves vêm junto; jogos que já estão aqui recebem só os saves mais novos.")
        alert.addButton(withTitle: String(localized: "Receber"))
        alert.addButton(withTitle: String(localized: "Recusar"))
        NSApp.activate()
        var take = false
        #if DEBUG
        // Development aid: EMBER_AUTOACCEPT=1 takes every offer.
        take = ProcessInfo.processInfo.environment["EMBER_AUTOACCEPT"] != nil
        #endif
        if !take { take = alert.runModal() == .alertFirstButtonReturn }
        let taken = take ? games : []
        connection.send(content: TransferProtocol.encode(.answer, json: taken.map(\.id)),
                        completion: .contentProcessed { _ in })
        guard !taken.isEmpty else {
            connection.cancel()
            return
        }
        let receiver = Receiver(connection: connection, games: taken)
        receiving = (taken[0].title, 0)
        receiver.next()
    }

    fileprivate func progress(_ title: String, _ fraction: Double) {
        receiving = (title, fraction)
    }

    fileprivate func finished(_ titles: [String], error: String?) {
        receiving = nil
        let library = MacLibrary.shared
        library.reload()
        for game in library.games where titles.contains(game.title) || titles.contains(game.originalTitle) {
            Task { await ControllerTypeStore.detect([game]) }
        }
        library.syncSaves()
        #if DEBUG
        FileHandle.standardError.write(Data("[ember-transfer] got \(titles), error \(error ?? "none"); library: \(library.games.map(\.id))\n".utf8))
        #endif
        if let error {
            library.lastError = error
        } else if !titles.isEmpty {
            library.notice = String(localized: "Chegaram do iPhone: \(titles.joined(separator: ", ")).")
        }
    }
}

/// Receives the files of one transfer, off the main thread.
private final class Receiver: @unchecked Sendable {
    private let connection: NWConnection
    private let games: [TransferProtocol.Offer.Game]
    private let total: Int64
    private var received: Int64 = 0
    private let staging: URL
    private var file: FileHandle?
    private var fileURL: URL?
    private var fileRemaining: Int64 = 0
    private var fileDate: Date?
    private var installed: [String] = []

    init(connection: NWConnection, games: [TransferProtocol.Offer.Game]) {
        self.connection = connection
        self.games = games
        total = max(1, games.reduce(0) { $0 + $1.bytes })
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        staging = support.appendingPathComponent("Incoming/\(UUID().uuidString)", isDirectory: true)
    }

    func next() {
        TransferProtocol.receiveOne(on: connection) { [self] kind, data in
            // A new file or the end of a game with the last file still
            // short: the iPhone stopped mid-file. Nothing is installed.
            if kind == .file || kind == .gameDone, fileRemaining > 0 {
                return fail(String(localized: "A transferência se perdeu no meio de um arquivo."))
            }
            switch kind {
            case .file:
                guard let header = try? JSONDecoder().decode(TransferProtocol.FileHeader.self, from: data),
                      games.contains(where: { $0.id == header.id }),
                      let path = TransferProtocol.safePath(header.path)
                else { return fail(String(localized: "O iPhone mandou um arquivo inesperado.")) }
                let url = staging.appendingPathComponent("\(header.id)/\(header.area.rawValue)/\(path)")
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: url.path, contents: nil)
                file = try? FileHandle(forWritingTo: url)
                fileURL = url
                fileRemaining = header.size
                fileDate = header.modified
                if header.size == 0 { closeFile() }
            case .chunk:
                guard let file, Int64(data.count) <= fileRemaining else {
                    return fail(String(localized: "A transferência se perdeu no meio de um arquivo."))
                }
                do { try file.write(contentsOf: data) } catch {
                    return fail(String(localized: "Não há espaço no Mac para receber os jogos."))
                }
                fileRemaining -= Int64(data.count)
                received += Int64(data.count)
                if fileRemaining == 0 { closeFile() }
                report()
            case .gameDone:
                let id = String(decoding: data, as: UTF8.self)
                if let game = games.first(where: { $0.id == id }) {
                    Self.install(id: id, from: staging.appendingPathComponent(id))
                    installed.append(game.title)
                }
            case .done:
                connection.cancel()
                try? FileManager.default.removeItem(at: staging)
                let titles = installed
                Task { @MainActor in MacTransferServer.shared.finished(titles, error: nil) }
                return
            default:
                return fail(String(localized: "O iPhone se desconectou antes de terminar. Os jogos que chegaram inteiros ficaram."))
            }
            next()
        }
    }

    private func closeFile() {
        try? file?.close()
        file = nil
        if let fileURL, let fileDate {
            try? FileManager.default.setAttributes([.modificationDate: fileDate], ofItemAtPath: fileURL.path)
        }
    }

    private var lastReport = Date.distantPast

    private func report() {
        guard Date().timeIntervalSince(lastReport) > 0.2 else { return }
        lastReport = Date()
        let fraction = Double(received) / Double(total)
        let title = games.first { !installed.contains($0.title) }?.title ?? ""
        Task { @MainActor in MacTransferServer.shared.progress(title, fraction) }
    }

    private func fail(_ message: String) {
        connection.cancel()
        try? file?.close()
        try? FileManager.default.removeItem(at: staging)
        let titles = installed
        Task { @MainActor in MacTransferServer.shared.finished(titles, error: message) }
    }

    // MARK: - Installing

    /// The game folder goes in as is when the game is new here; saves and
    /// states always merge, the newer file winning.
    private static func install(id: String, from folder: URL) {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let game = GameImporter.gamesFolder.appendingPathComponent(id, isDirectory: true)
        let incomingGame = folder.appendingPathComponent(TransferProtocol.Area.game.rawValue)
        let stash = documents.appendingPathComponent(
            "Backups/\(id)/\(String(localized: "Antes do iPhone")) \(Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)).replacingOccurrences(of: ":", with: "."))")

        if fm.fileExists(atPath: incomingGame.path) {
            if !fm.fileExists(atPath: game.path) {
                try? fm.createDirectory(at: GameImporter.gamesFolder, withIntermediateDirectories: true)
                try? fm.moveItem(at: incomingGame, to: game)
            } else {
                // Only the saves the game keeps in its own folder.
                merge(incomingGame, into: game, stash: stash.appendingPathComponent("Games"), only: { path in
                    SaveManager.isGameFolderSaveName((path as NSString).lastPathComponent) && !path.contains("/")
                        || path.lowercased().hasPrefix("save data/")
                })
            }
        }
        merge(folder.appendingPathComponent(TransferProtocol.Area.userData.rawValue),
              into: documents.appendingPathComponent("UserData/\(id)"), stash: stash.appendingPathComponent("UserData"))
        merge(folder.appendingPathComponent(TransferProtocol.Area.states.rawValue),
              into: support.appendingPathComponent("States/\(id)"), stash: stash.appendingPathComponent("States"))
        // Covers named by the game id only.
        merge(folder.appendingPathComponent(TransferProtocol.Area.covers.rawValue),
              into: support.appendingPathComponent("Covers"), stash: stash.appendingPathComponent("Covers"),
              only: { $0 == "\(id).jpg" || $0 == "\(id)-custom.jpg" })
    }

    /// Copies each file that is new or newer than the one here.
    private static func merge(_ source: URL, into target: URL, stash: URL, only: (String) -> Bool = { _ in true }) {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]) else { return }
        let base = source.standardizedFileURL.path
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            let relative = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            guard only(relative) else { continue }
            let destination = target.appendingPathComponent(relative)
            let incomingDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if fm.fileExists(atPath: destination.path) {
                let hereDate = (try? destination.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                guard incomingDate > hereDate else { continue }
                let kept = stash.appendingPathComponent(relative)
                try? fm.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.copyItem(at: destination, to: kept)
                try? fm.removeItem(at: destination)
            }
            try? fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: url, to: destination)
        }
    }
}
