import SwiftUI
import UIKit

/// Everything on top of the game: the skin (artwork and touch), the
/// loading screen, and the in-game menu.
struct ControlsOverlay: View {
    @ObservedObject private var layout = GameLayout.shared
    @ObservedObject private var session = EngineSession.shared
    @ObservedObject private var skins = SkinStore.shared
    @ObservedObject private var controllers = ControllerMonitor.shared
    @State private var showingMenu = false
    @State private var quitting = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let portrait = size.height >= size.width
            let skinLayout = skins.layout(portrait: portrait)
            // Landscape with a controller in hand: the buttons step away.
            let hideButtons = !portrait && controllers.connected && AppSettings.hideControlsWithController
            let opacity = (!portrait && skinLayout.translucent) ? AppSettings.landscapeOpacity : 1

            ZStack(alignment: .topLeading) {
                if !hideButtons {
                    SkinControllerView(skin: skins.current, layout: skinLayout,
                                       pictureRect: layout.pictureRect,
                                       opacity: opacity, onMenu: openMenu)
                }
                // Every skin needs a way to the menu.
                if hideButtons || !skinLayout.hasMenuButton {
                    FloatingMenuButton(action: openMenu)
                        .padding(.top, geo.safeAreaInsets.top + 8)
                        .padding(.leading, geo.safeAreaInsets.leading + 12)
                }
            }
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        .overlay {
            // Until the engine draws its first frame.
            if layout.pictureRect == .zero {
                LoadingScreen(title: session.currentGame?.title ?? "")
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.35), value: layout.pictureRect == .zero)
        .sheet(isPresented: $showingMenu, onDismiss: menuDismissed) {
            GameMenuView(title: session.currentGame?.title ?? "") {
                quitting = true
                session.quit()
            }
            .presentationDetents([.height(350)])
        }
        .onAppear(perform: autoMenuForDevelopment)
    }

    private func openMenu() {
        guard !showingMenu else { return }
        mkxp_requestPause()
        showingMenu = true
    }

    /// Closing the menu resumes the game, unless the player quit:
    /// ending the engine already wakes it.
    private func menuDismissed() {
        PauseSnapshot.shared.clear()
        if !quitting { mkxp_requestResume() }
    }

    /// Development aid: EMBER_AUTOMENU=<seconds> opens the menu.
    private func autoMenuForDevelopment() {
        #if DEBUG
        guard let seconds = ProcessInfo.processInfo.environment["EMBER_AUTOMENU"].flatMap(Double.init)
        else { return }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            openMenu()
        }
        #endif
    }
}

/// The menu button for skins that have none, or when the buttons hide.
private struct FloatingMenuButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.controlLabel)
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .glassEffect(Theme.controlGlass.interactive(), in: Circle())
        .accessibilityLabel("Menu")
    }
}

/// Shown while the engine boots: the flame and "Acendendo…".
private struct LoadingScreen: View {
    let title: String

    var body: some View {
        ZStack {
            Theme.controllerBackground.ignoresSafeArea()
            VStack(spacing: 14) {
                EmberFlame(size: 54)
                    .symbolEffect(.pulse)
                Text("Acendendo…")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color(hex: 0xF4E9D8))
                if !title.isEmpty {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(Color(hex: 0xB9A794))
                }
            }
        }
    }
}
