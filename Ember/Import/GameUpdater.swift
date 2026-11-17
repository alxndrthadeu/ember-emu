import Foundation

/// A new version of a game already on the shelf (fan games update
/// often): the new files take the old game's place and everything the
/// player has stays, because the game keeps its id. Saves in the game
/// folder come along (and are kept in Backups), UserData/<id> with
/// Essentials saves stays, and so do save states, cover, controls,
/// name and history.
enum GameUpdater {
    struct Offer: Identifiable, Equatable {
        /// The version just imported, in a folder of its own.
        let incoming: GameEntry
        /// The game on the shelf it looks like.
        let existing: GameEntry
        var id: String { incoming.id }
    }

    /// The shelf game the newly imported one is a version of: same
    /// title in Game.ini (renaming on the shelf doesn't matter).
    static func existingVersion(of incoming: GameEntry, in games: [GameEntry]) -> GameEntry? {
        games.first { $0.id != incoming.id && $0.originalTitle == incoming.originalTitle }
    }

    /// Moves the new version into the old game's place. Runs off the
    /// main thread. Returns how many saves came along.
    static func update(_ offer: Offer) throws -> Int {
        let fm = FileManager.default
        let carried = try SaveManager.carryGameFolderSaves(of: offer.existing, into: offer.incoming.folder)
        let old = offer.existing.folder
        let set = old.deletingLastPathComponent()
            .appendingPathComponent(".replaced-\(UUID().uuidString)", isDirectory: true)
        // Swap, then delete: if the move fails the old game is still there.
        try fm.moveItem(at: old, to: set)
        do {
            try fm.moveItem(at: offer.incoming.folder, to: old)
        } catch {
            try? fm.moveItem(at: set, to: old)
            throw error
        }
        try? fm.removeItem(at: set)
        return carried
    }
}
