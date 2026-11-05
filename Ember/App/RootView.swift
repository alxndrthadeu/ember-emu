import SwiftUI

enum AppTab: Hashable {
    case library
    case importGames
    case settings
}

/// Which tab is showing. Screens switch tabs through it (the empty
/// library's "Importar jogo", an import that just started).
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    @Published var tab: AppTab = .library
    /// A home screen quick action waiting for the library to handle it.
    @Published var quickAction: QuickAction?
    private init() {}
}

/// The app's tabs, in the system's Liquid Glass tab bar.
struct RootView: View {
    @ObservedObject private var router = AppRouter.shared
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
                SettingsView()
                    .tabItem { Label("Ajustes", systemImage: "gearshape") }
                    .tag(AppTab.settings)
            }
            .tint(Theme.accent)
        }
    }
}
