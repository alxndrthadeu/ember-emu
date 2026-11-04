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
    private init() {}
}

/// The app's tabs, in the system's Liquid Glass tab bar.
struct RootView: View {
    @ObservedObject private var router = AppRouter.shared

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("Biblioteca", systemImage: "square.grid.2x2.fill", value: AppTab.library) {
                LibraryView()
            }
            Tab("Importar", systemImage: "plus", value: AppTab.importGames) {
                ImportView()
            }
            Tab("Ajustes", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tint(Theme.accent)
    }
}
