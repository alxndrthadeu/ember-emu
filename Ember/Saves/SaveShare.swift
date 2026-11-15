import Foundation
import ZIPFoundation

/// Sending saves to another iPhone: a ".embersave" package (a zip with
/// the saves and a small manifest naming the game). Shared through the
/// share sheet, so bringing two iPhones together starts AirDrop; on
/// the other side "Open in Ember" puts the saves into the same game.
/// Only saves travel, never the game itself.
enum SaveShare {
    static let fileExtension = "embersave"
    private static let manifestName = "ember-save.json"

    struct Manifest: Codable {
        var format = 1
        let gameID: String
        let title: String
        let originalTitle: String
        let exported: Date
    }

    enum ShareError: LocalizedError {
        case notAPackage
        case gameMissing(String)

        var errorDescription: String? {
            switch self {
            case .notAPackage:
                String(localized: "Este arquivo não é um pacote de saves do Ember.")
            case .gameMissing(let title):
                String(localized: "Estes saves são de “\(title)”. Importe o jogo primeiro e abra o arquivo de novo.")
            }
        }
    }

    /// Builds the package for `game`.
    static func package(_ game: GameEntry) throws -> URL {
        let saves = SaveManager.saves(for: game)
        guard !saves.isEmpty else { throw SaveManager.SaveError.noSaves(game.title) }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("Share-\(UUID().uuidString)")
        let staging = work.appendingPathComponent("saves")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        for save in saves {
            let target = staging.appendingPathComponent(save.id)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: save.url, to: target)
        }
        let manifest = Manifest(gameID: game.id, title: game.title, originalTitle: game.originalTitle, exported: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: staging.appendingPathComponent(manifestName))

        let safeTitle = game.title.replacingOccurrences(of: "/", with: "-")
        let package = work.appendingPathComponent("\(safeTitle).\(fileExtension)")
        try fm.zipItem(at: staging, to: package, shouldKeepParent: false)
        return package
    }

    /// Puts the saves of a received package into the matching game.
    /// Saves already there are kept in Documents/Backups first.
    /// Returns the game and how many files were placed.
    @MainActor
    static func receive(_ url: URL) throws -> (GameEntry, Int) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("Received-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: work) }
        do {
            try fm.unzipItem(at: url, to: work)
        } catch {
            throw ShareError.notAPackage
        }
        let manifestURL = work.appendingPathComponent(manifestName)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? decoder.decode(Manifest.self, from: data)
        else { throw ShareError.notAPackage }
        try? fm.removeItem(at: manifestURL)

        // The same game: same folder id, else the same .ini title, else
        // the same name shown in the library.
        let games = LibraryStore.shared.games
        guard let game = games.first(where: { $0.id == manifest.gameID })
            ?? games.first(where: { $0.originalTitle == manifest.originalTitle })
            ?? games.first(where: { $0.title == manifest.title })
        else { throw ShareError.gameMissing(manifest.title) }

        let count = try SaveManager.importSaves(from: [work], into: game)
        return (game, count)
    }
}
