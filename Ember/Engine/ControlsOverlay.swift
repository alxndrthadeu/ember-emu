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
    @State private var showingStates = false
    @State private var toast: String?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let portrait = size.height >= size.width
            // A keyboard button by the gear, for every game: old games poll a
            // PC keyboard, and on newer ones it is the way in if the game's
            // own text prompt never brings the keyboard up. (GameTextField
            // sends text or key taps, whichever the game is reading.)
            let wantsKeyboard = true
            let skinLayout = skins.layout(portrait: portrait, keyboard: wantsKeyboard)
            // Landscape with a controller in hand: the buttons step away.
            let hideButtons = !portrait && controllers.connected && AppSettings.hideControlsWithController
            let opacity = (!portrait && skinLayout.translucent) ? AppSettings.landscapeOpacity : 1

            ZStack(alignment: .topLeading) {
                if !hideButtons {
                    SkinControllerView(skin: skins.current, layout: skinLayout,
                                       pictureRect: layout.onTV ? .zero : layout.pictureRect,
                                       opacity: opacity, showKeyboard: wantsKeyboard,
                                       onMenu: openMenu, onKeyboard: session.openKeyboard)
                }
                // The game is on the TV: say so where the picture was.
                if layout.onTV, let screen = skinLayout.screen {
                    let sx = size.width / skinLayout.mappingSize.width
                    let sy = size.height / skinLayout.mappingSize.height
                    let rect = screen.applying(.init(scaleX: sx, y: sy))
                    PlayingOnTVLabel()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                // PC-style readout in the picture's corner (this stack fills
                // the screen from its top-left, like pictureRect).
                if !layout.onTV {
                    PerformanceHUD()
                        .offset(x: layout.pictureRect.minX + 6, y: layout.pictureRect.minY + 6)
                }

                // Every skin needs a way to the menu.
                if hideButtons || !skinLayout.hasMenuButton {
                    HStack(spacing: 10) {
                        FloatingMenuButton(action: openMenu)
                        if wantsKeyboard {
                            KeyboardButton(action: session.openKeyboard)
                        }
                    }
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
        .onChange(of: layout.pictureRect == .zero) {
            // The engine's audio is up once it draws.
            if layout.pictureRect != .zero { GameAudio.shared.apply() }
        }
        .sheet(isPresented: $showingMenu, onDismiss: menuDismissed) {
            GameMenuView(title: session.currentGame?.title ?? "",
                         onSaveState: { runState("save", slot: StateStore.newSlot()) },
                         onShowStates: { afterMenu { showingStates = true } }) {
                quitting = true
                session.quit()
            }
            .presentationDetents([.height(500)])
        }
        .sheet(isPresented: $showingStates) {
            if let game = session.currentGame {
                StatesSheet(gameID: game.id) { state in
                    showingStates = false
                    runState("load", slot: state.slot)
                }
                .presentationDetents([.medium, .large])
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.onHighlight)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .emberGlass(.regular.tint(Theme.highlight), in: Capsule())
                    .padding(.top, 54)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: toast)
        .onChange(of: controllers.justConnected) {
            if let name = controllers.justConnected {
                show(String(localized: "\(name) conectado"))
                controllers.justConnected = nil
            }
        }
        .onAppear {
            // A profile can put Ember's menu on any button.
            ControlMapper.shared.onMenu = { openMenu() }
            autoMenuForDevelopment()
        }
    }

    /// After the menu sheet is gone (and the game resumed).
    private func afterMenu(_ body: @escaping () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            body()
        }
    }

    /// Saves or loads a state once the game runs again, then tells the
    /// player how it went.
    private func runState(_ verb: String, slot: String) {
        afterMenu {
            Task { @MainActor in
                let outcome = await session.requestState(verb, slot: slot)
                switch outcome {
                case .done: show(verb == "save" ? String(localized: "Estado salvo") : String(localized: "Estado carregado"))
                case .busy(let reason): show(StateStore.busyText(reason))
                case .failed: show(verb == "save" ? String(localized: "Não deu para salvar o estado neste jogo") : String(localized: "Não deu para carregar o estado"))
                case .noAnswer: show(String(localized: "O jogo não respondeu. Tente de novo andando pelo mapa"))
                }
            }
        }
    }

    private func show(_ message: String) {
        toast = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if toast == message { toast = nil }
        }
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
        .emberGlass(Theme.controlGlass.interactive(), in: Circle())
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
