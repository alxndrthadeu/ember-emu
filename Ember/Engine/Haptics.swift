import UIKit

/// Light haptic feedback on button presses.
@MainActor
enum Haptics {
    private static let generator = UIImpactFeedbackGenerator(style: .light)

    static func tap() {
        guard AppSettings.haptics else { return }
        generator.impactOccurred()
    }

    /// Something finished: a state saved, a game imported.
    static func success() {
        guard AppSettings.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Something did not work.
    static func failure() {
        guard AppSettings.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
