import SwiftUI
import UIKit

/// The on-screen controller, a Game Boy Advance layout: D-pad, A, B,
/// L, R, Start and Select, plus a gear for the game settings.
///
/// Portrait: the game sits at the top and the controller fills the
/// space under it. Landscape: the game fills the screen and the
/// controls float over it. Phase 3 turns this into skins.
struct ControlsOverlay: View {
    @ObservedObject private var layout = GameLayout.shared
    @ObservedObject private var session = EngineSession.shared
    @State private var showingMenu = false
    @State private var quitting = false

    var body: some View {
        GeometryReader { geo in
            let full = geo.frame(in: .global)
            let portrait = full.height >= full.width
            // The controller starts right under the picture.
            // GameViewController sizes the picture to the full width,
            // so there is no gap between them.
            let pictureBottom = layout.pictureRect.maxY > 0
                ? layout.pictureRect.maxY : full.minY + full.width * 0.75
            let controllerHeight = max(0, full.maxY + geo.safeAreaInsets.bottom - pictureBottom)

            ZStack(alignment: .bottom) {
                Color.clear

                if portrait {
                    Theme.controllerBackground
                        .frame(height: controllerHeight)
                        .ignoresSafeArea(edges: .bottom)
                }

                controller(portrait: portrait)
                    .frame(height: portrait ? controllerHeight - geo.safeAreaInsets.bottom : nil)
                    .frame(maxHeight: portrait ? nil : .infinity)
            }
        }
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
            .presentationDetents([.height(260)])
            .presentationDragIndicator(.visible)
        }
    }

    /// Closing the menu resumes the game, unless the player quit:
    /// ending the engine already wakes it.
    private func menuDismissed() {
        PauseSnapshot.shared.clear()
        if !quitting { mkxp_requestResume() }
    }

    private func controller(portrait: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                ShoulderButton(title: "L", key: .l)
                Spacer()
                GearButton {
                    mkxp_requestPause()
                    showingMenu = true
                }
                Spacer()
                ShoulderButton(title: "R", key: .r)
            }
            Spacer(minLength: 12)
            HStack(alignment: .center) {
                DPad()
                Spacer()
                FaceButtons()
            }
            Spacer(minLength: 12)
            HStack(spacing: 18) {
                PillButton(title: "Select", key: .select)
                PillButton(title: "Start", key: .start)
            }
        }
        .padding(.horizontal, portrait ? 20 : 32)
        .padding(.top, portrait ? 16 : 12)
        .padding(.bottom, portrait ? 12 : 16)
    }
}

// MARK: - Buttons

/// Holds a key down while the finger is on the control.
private struct HoldGesture: ViewModifier {
    let key: GameKey
    @Binding var pressed: Bool

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    Haptics.tap()
                    key.press()
                }
                .onEnded { _ in
                    pressed = false
                    key.release()
                })
    }
}

/// A sits up and to the right of B, as on a GBA.
private struct FaceButtons: View {
    var body: some View {
        ZStack {
            RoundButton(title: "B", key: .back).offset(x: -38, y: 22)
            RoundButton(title: "A", key: .confirm).offset(x: 38, y: -22)
        }
        .frame(width: 156, height: 124)
    }
}

private struct RoundButton: View {
    let title: String
    let key: GameKey
    @State private var pressed = false

    var body: some View {
        Text(title)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.controlLabel)
            .frame(width: 68, height: 68)
            .background(Circle().fill(pressed ? Theme.controlFillPressed : Theme.controlFill))
            .overlay(Circle().stroke(Theme.controlStroke, lineWidth: 1))
            .contentShape(Circle().inset(by: -8))
            .modifier(HoldGesture(key: key, pressed: $pressed))
    }
}

private struct ShoulderButton: View {
    let title: String
    let key: GameKey
    @State private var pressed = false

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.controlLabel)
            .frame(width: 92, height: 38)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(pressed ? Theme.controlFillPressed : Theme.controlFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.controlStroke, lineWidth: 1))
            .contentShape(Rectangle().inset(by: -8))
            .modifier(HoldGesture(key: key, pressed: $pressed))
    }
}

private struct PillButton: View {
    let title: String
    let key: GameKey
    @State private var pressed = false

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(Theme.controlLabel)
            .frame(width: 72, height: 26)
            .background(Capsule().fill(pressed ? Theme.controlFillPressed : Theme.controlFill))
            .overlay(Capsule().stroke(Theme.controlStroke, lineWidth: 1))
            .contentShape(Capsule().inset(by: -10))
            .modifier(HoldGesture(key: key, pressed: $pressed))
    }
}

private struct GearButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 17))
                .foregroundStyle(Theme.controlLabel)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Theme.controlFill))
                .overlay(Circle().stroke(Theme.controlStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Menu")
    }
}

/// Shown while the engine boots: the flame and "Acendendo…".
private struct LoadingScreen: View {
    let title: String

    var body: some View {
        ZStack {
            Theme.controllerBackground.ignoresSafeArea()
            VStack(spacing: 18) {
                PixelFlame(cell: 8)
                    .environment(\.colorScheme, .dark)
                Text("Acendendo…")
                    .pixelFont(26)
                    .foregroundStyle(Color(hex: 0xF4E9D8))
                if !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(hex: 0xB9A794))
                }
            }
        }
    }
}
