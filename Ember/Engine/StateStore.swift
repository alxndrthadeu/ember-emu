import Foundation
import UIKit

/// Save states ("save rápido"), kept by Ember apart from the game's own
/// saves. The work happens inside the game, in ember_quicksave.rb; this
/// side writes requests and reads answers in a per-game folder.
enum StateStore {
    /// The slot written when the app leaves the screen and every few
    /// minutes on the map; "Continuar" resumes from it.
    static let autoSlot = "auto"
    /// How often the game saves the auto slot while quiet on the map.
    static let autoSeconds = 120

    struct SaveState: Identifiable, Hashable {
        let slot: String
        let date: Date
        let thumbnail: URL?
        var id: String { slot }
        var isAuto: Bool { slot == StateStore.autoSlot }
    }

    enum Outcome: Equatable {
        case done
        /// Not a quiet moment (battle, message, event, menu...).
        case busy(String)
        case failed(String)
        /// The game never answered (paused, or a game the script cannot drive).
        case noAnswer
    }

    static func folder(for gameID: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appendingPathComponent("States/\(gameID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func states(for gameID: String) -> [SaveState] {
        let dir = folder(for: gameID)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names
            .filter { $0.hasSuffix(".state") }
            .compactMap { name -> SaveState? in
                let slot = String(name.dropLast(".state".count))
                let url = dir.appendingPathComponent(name)
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate ?? .distantPast
                let png = dir.appendingPathComponent("\(slot).png")
                return SaveState(slot: slot, date: date,
                                 thumbnail: FileManager.default.fileExists(atPath: png.path) ? png : nil)
            }
            .sorted { $0.date > $1.date }
    }

    static func autoState(for gameID: String) -> SaveState? {
        states(for: gameID).first { $0.isAuto }
    }

    static func delete(_ state: SaveState, gameID: String) {
        let dir = folder(for: gameID)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(state.slot).state"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(state.slot).png"))
    }

    /// A new manual slot name.
    static func newSlot() -> String {
        "s\(Int(Date().timeIntervalSince1970))"
    }

    /// Environment for the engine, set before it starts: the script
    /// reads it through Ruby's ENV.
    static func prepareEnvironment(gameID: String, resumeSlot: String?) {
        let dir = folder(for: gameID)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("request"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("response"))
        setenv("EMBER_STATE_DIR", dir.path, 1)
        setenv("EMBER_AUTOSTATE_SECONDS", "\(autoSeconds)", 1)
        if let resumeSlot {
            setenv("EMBER_RESUME_SLOT", resumeSlot, 1)
        } else {
            unsetenv("EMBER_RESUME_SLOT")
        }
    }

    /// Asks the running game to save or load a slot, and waits for its
    /// answer. The game must be running (not paused) to answer.
    @MainActor
    static func request(_ verb: String, slot: String, gameID: String,
                        timeout: TimeInterval = 3) async -> Outcome {
        let dir = folder(for: gameID)
        let response = dir.appendingPathComponent("response")
        try? FileManager.default.removeItem(at: response)
        do {
            try "\(verb):\(slot)".write(to: dir.appendingPathComponent("request"), atomically: true, encoding: .utf8)
        } catch {
            return .failed(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var lastBusy: String?
        while Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            guard let text = try? String(contentsOf: response, encoding: .utf8) else { continue }
            if text.hasPrefix("ok:\(verb)") { return .done }
            if text.hasPrefix("error:") { return .failed(String(text.dropFirst(6))) }
            if text.hasPrefix("busy:") {
                // Keep waiting: the game retries on later frames.
                lastBusy = String(text.dropFirst(5))
                try? FileManager.default.removeItem(at: response)
            }
        }
        // Withdraw a request the game never took.
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("request"))
        return lastBusy.map { .busy($0) } ?? .noAnswer
    }

    /// A short, player-facing reason for a busy answer.
    static func busyText(_ reason: String) -> String {
        switch reason {
        case "battle": "Termine a batalha para salvar o estado"
        case "message", "event": "Termine a conversa ou o evento para salvar o estado"
        case "menu": "Feche o menu do jogo para salvar o estado"
        default: "Volte a andar pelo mapa para salvar o estado"
        }
    }
}
