import Foundation

/// Where a game's saves and settings live, apart from its files.
enum GameStorage {
    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Saves and settings, kept apart from the game files so a game
    /// can be replaced without losing them.
    static func userDataFolder(for game: GameEntry) -> URL {
        let folder = documents.appendingPathComponent("UserData/\(game.id)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
