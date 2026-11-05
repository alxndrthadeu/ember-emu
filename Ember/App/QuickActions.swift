import StoreKit
import UIKit

/// The menu that opens when the app icon is held: continue the last
/// game, import a game, or turn on the Wi-Fi transfer.
enum QuickAction: String {
    case continueLast = "com.alexandrethadeu.ember.continue"
    case importGame = "com.alexandrethadeu.ember.import"
    case wifi = "com.alexandrethadeu.ember.wifi"

    /// Rebuilds the menu, so "Continuar" names the last game played.
    /// `library` is passed by the store itself while it starts up
    /// (reading LibraryStore.shared then would recurse into its init).
    @MainActor
    static func refresh(_ library: LibraryStore = .shared) {
        var items: [UIApplicationShortcutItem] = []
        if let recent = library.recent {
            items.append(UIApplicationShortcutItem(
                type: continueLast.rawValue,
                localizedTitle: String(localized: "Continuar"),
                localizedSubtitle: recent.title,
                icon: UIApplicationShortcutIcon(systemImageName: "play.fill")))
        }
        items.append(UIApplicationShortcutItem(
            type: importGame.rawValue,
            localizedTitle: String(localized: "Importar jogo"),
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "folder.badge.plus")))
        items.append(UIApplicationShortcutItem(
            type: wifi.rawValue,
            localizedTitle: String(localized: "Enviar pelo Wi-Fi"),
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(systemImageName: "wifi")))
        UIApplication.shared.shortcutItems = items
    }
}

/// When to ask for a rating: right after a game ends well (the session
/// lasted 10 minutes or more), once the player has had three such
/// sessions, and once per app version. Never during play or after an
/// error. iOS itself also caps the prompt at three times a year.
enum ReviewPrompt {
    private static let longSession: TimeInterval = 10 * 60
    private static let askedKey = "review.askedVersion"

    static var isGoodMoment: Bool {
        let sessions = PlayHistory.sessions
        guard let last = sessions.first, last.duration >= longSession else { return false }
        guard sessions.filter({ $0.duration >= longSession }).count >= 3 else { return false }
        return UserDefaults.standard.string(forKey: askedKey) != version
    }

    static func markAsked() {
        UserDefaults.standard.set(version, forKey: askedKey)
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}
