import SwiftUI
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        Theme.styleNavigationBars()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: LibraryView().fontDesign(.rounded))
        window.tintColor = UIColor(Theme.accent)
        window.makeKeyAndVisible()
        self.window = window

        EngineSession.shared.launcherWindow = window

        importOpenedFiles(connectionOptions.urlContexts)
    }

    /// "Open in Ember" from the Files app or the share sheet.
    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        importOpenedFiles(contexts)
    }

    private func importOpenedFiles(_ contexts: Set<UIOpenURLContext>) {
        let urls = contexts.map(\.url).filter(\.isFileURL)
        guard !urls.isEmpty else { return }
        LibraryStore.shared.importItems(urls)
    }
}
