import SwiftUI
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: RootView().fontDesign(.rounded))
        window.tintColor = UIColor(Theme.accent)
        window.makeKeyAndVisible()
        self.window = window

        EngineSession.shared.launcherWindow = window

        importOpenedFiles(connectionOptions.urlContexts)
        if let item = connectionOptions.shortcutItem {
            AppRouter.shared.quickAction = QuickAction(rawValue: item.type)
        }
        QuickAction.refresh()
    }

    /// A quick action from the app icon while the app was running.
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        let action = QuickAction(rawValue: shortcutItem.type)
        AppRouter.shared.quickAction = action
        completionHandler(action != nil)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        QuickAction.refresh()
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
