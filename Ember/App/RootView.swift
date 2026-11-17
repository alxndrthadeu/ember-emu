import SwiftUI

enum AppTab: Hashable {
    case library
    case importGames
    case mac
    case settings
}

/// Which tab is showing. Screens switch tabs through it (the empty
/// library's "Importar jogo", an import that just started).
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var tab: AppTab = .library
    /// A home screen quick action waiting for the library to handle it.
    var quickAction: QuickAction?
    /// A game to open, asked by Siri or Shortcuts (its id).
    var gameToOpen: String?
    private init() {}
}

/// The app's tabs, in the system's Liquid Glass tab bar.
struct RootView: View {
    @Bindable private var router = AppRouter.shared
    /// Once per launch, over everything until it fades.
    @State private var showingSplash = true

    var body: some View {
        ZStack {
            tabs
            if showingSplash {
                SplashView { showingSplash = false }
                    .zIndex(1)
            }
        }
    }

    @ViewBuilder
    private var tabs: some View {
        if #available(iOS 18, *), !EmberCompat.forceLegacy {
            TabView(selection: $router.tab) {
                Tab("Biblioteca", image: "Cartridge", value: AppTab.library) {
                    LibraryView()
                }
                Tab("Importar", systemImage: "folder.badge.plus", value: AppTab.importGames) {
                    ImportView()
                }
                Tab("Mac", systemImage: "macbook.and.iphone", value: AppTab.mac) {
                    MacTab()
                }
                Tab("Ajustes", systemImage: "gearshape", value: AppTab.settings) {
                    SettingsView()
                }
            }
            .tint(Theme.accent)
        } else {
            // iOS 17: the Tab type does not exist yet.
            TabView(selection: $router.tab) {
                LibraryView()
                    .tabItem { Label("Biblioteca", image: "Cartridge") }
                    .tag(AppTab.library)
                ImportView()
                    .tabItem { Label("Importar", systemImage: "folder.badge.plus") }
                    .tag(AppTab.importGames)
                MacTab()
                    .tabItem { Label("Mac", systemImage: "macbook.and.iphone") }
                    .tag(AppTab.mac)
                SettingsView()
                    .tabItem { Label("Ajustes", systemImage: "gearshape") }
                    .tag(AppTab.settings)
            }
            .tint(Theme.accent)
        }
    }
}
