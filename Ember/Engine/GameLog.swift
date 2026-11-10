import Foundation
import UIKit

/// One log file per game session: everything the engine and the game
/// print, plus Ember's own events and the errors shown to the player.
///
/// Logs live in Application Support/Logs/<game id>/; the newest ten
/// sessions of each game are kept.
final class GameLog: @unchecked Sendable {
    static let shared = GameLog()

    /// A session line marks an error with this prefix (LogsView looks
    /// for it).
    static let errorMarker = "[erro]"
    private static let keep = 10
    private static let maxBytes = 4 * 1_048_576

    private let queue = DispatchQueue(label: "ember.gamelog")
    private var handle: FileHandle?
    private var written = 0
    private var pipe: Pipe?
    private var savedOut: Int32 = -1
    private var savedErr: Int32 = -1

    private init() {}

    static func folder(for gameID: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appendingPathComponent("Logs/\(gameID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Session

    @MainActor
    func begin(game: GameEntry, details: [String]) {
        end()
        let folder = Self.folder(for: game.id)
        prune(folder)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = folder.appendingPathComponent("\(formatter.string(from: Date())).log")
        FileManager.default.createFile(atPath: url.path, contents: nil)

        queue.sync {
            handle = try? FileHandle(forWritingTo: url)
            written = 0
        }
        let device = UIDevice.current
        let app = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        var header = [
            "Ember \(app) · \(device.model) · iOS \(device.systemVersion)",
            "Jogo: \(game.title) (\(game.id))",
        ]
        header += details
        header.append(String(repeating: "-", count: 60))
        append(header.joined(separator: "\n") + "\n")
        captureOutput()
    }

    func end() {
        restoreOutput()
        queue.sync {
            try? handle?.close()
            handle = nil
        }
    }

    /// One of Ember's own events.
    func note(_ text: String) {
        append("[ember \(time())] \(text)\n")
    }

    /// An error the player saw, or one Ember caught.
    func error(_ text: String) {
        append("\(Self.errorMarker) \(time()) \(text)\n")
    }

    // MARK: Engine output

    /// Sends stdout and stderr through a pipe: each chunk goes to the log
    /// file and on to the original output (Xcode's console keeps working).
    private func captureOutput() {
        guard pipe == nil else { return }
        let pipe = Pipe()
        fflush(stdout)
        fflush(stderr)
        setvbuf(stdout, nil, _IOLBF, 0)
        savedOut = dup(STDOUT_FILENO)
        savedErr = dup(STDERR_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        let original = savedOut
        pipe.fileHandleForReading.readabilityHandler = { [weak self] reader in
            let data = reader.availableData
            guard !data.isEmpty else { return }
            data.withUnsafeBytes { _ = write(original, $0.baseAddress, data.count) }
            self?.append(data)
        }
        self.pipe = pipe
    }

    private func restoreOutput() {
        guard let pipe else { return }
        fflush(stdout)
        fflush(stderr)
        if savedOut >= 0 { dup2(savedOut, STDOUT_FILENO); close(savedOut) }
        if savedErr >= 0 { dup2(savedErr, STDERR_FILENO); close(savedErr) }
        savedOut = -1
        savedErr = -1
        pipe.fileHandleForReading.readabilityHandler = nil
        self.pipe = nil
    }

    // MARK: Writing

    private func append(_ text: String) {
        append(Data(text.utf8))
    }

    private func append(_ data: Data) {
        queue.async { [self] in
            guard let handle, written < Self.maxBytes else { return }
            handle.write(data)
            written += data.count
            if written >= Self.maxBytes {
                handle.write(Data("\n[ember] registro cortado em 4 MB\n".utf8))
            }
        }
    }

    private func time() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    private func prune(_ folder: URL) {
        let logs = ((try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in logs.dropFirst(Self.keep - 1) {
            try? FileManager.default.removeItem(at: old)
        }
    }
}
