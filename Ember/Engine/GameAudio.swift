import AVFoundation
import Foundation

/// The game's sound, and how it shares the speaker with other apps.
@MainActor
final class GameAudio: ObservableObject {
    static let shared = GameAudio()

    /// OpenAL's AL_GAIN.
    private static let alGain: Int32 = 0x100A

    /// The game's sound on or off. Applies at once.
    @Published var soundOn = UserDefaults.standard.object(forKey: "settings.gameSound") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(soundOn, forKey: "settings.gameSound")
            apply()
        }
    }

    /// Let music from other apps keep playing under the game.
    @Published var mixWithOthers = UserDefaults.standard.bool(forKey: "settings.mixAudio") {
        didSet {
            UserDefaults.standard.set(mixWithOthers, forKey: "settings.mixAudio")
            configureSession()
        }
    }

    /// Whether other apps' audio plays on: asked for, or the game is
    /// silent anyway.
    var mixes: Bool { mixWithOthers || !soundOn }

    private init() {}

    /// Before the engine starts: the audio session for the game.
    /// Ambient mixes with other apps (and, like most games, follows the
    /// silent switch); solo ambient stops other apps' audio.
    func configureSession() {
        let session = AVAudioSession.sharedInstance()
        if mixes {
            try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        } else {
            try? session.setCategory(.soloAmbient, mode: .default)
        }
        try? session.setActive(true)
    }

    /// Mutes or unmutes every sound of the running game. Harmless before
    /// the engine's audio exists (OpenAL ignores it without a context).
    func apply() {
        alListenerf(Self.alGain, soundOn ? 1 : 0)
        configureSession()
        #if DEBUG
        var gain: Float = -1
        alGetListenerf(Self.alGain, &gain)
        print("[ember-audio] game sound \(soundOn ? "on" : "off"), listener gain \(gain), mixes \(mixes), category \(AVAudioSession.sharedInstance().category.rawValue)")
        #endif
    }
}
