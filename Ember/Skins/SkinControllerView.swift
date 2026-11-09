import GameController
import SwiftUI
import UIKit


/// A skin on screen: its artwork, cut open where the game picture is,
/// and a touch layer that turns fingers into game input.
struct SkinControllerView: View {
    let skin: Skin
    let layout: SkinLayout
    /// The game picture, in this view's coordinates: the artwork leaves
    /// a hole there, because the game draws below the controls.
    let pictureRect: CGRect
    let opacity: Double
    /// Old games: a keyboard button next to the menu button.
    var showKeyboard = false
    let onMenu: () -> Void
    var onKeyboard: () -> Void = {}

    @StateObject private var touches = SkinTouchState()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                artwork(size: geo.size)
                    .opacity(opacity)
                    .mask {
                        HoleShape(hole: pictureRect)
                            .fill(style: FillStyle(eoFill: true))
                    }
                // Built-in controls stay visible when they sit over the
                // picture (landscape on a near-square screen like an open
                // iPhone Duo). On phones they never overlap it.
                if case .builtIn(let style) = skin.source {
                    BuiltInSkinArt(style: style, layout: layout, pressed: touches.pressed,
                                   held: touches.held, knobs: touches.knobs, layer: .controls)
                        .opacity(opacity)
                        .allowsHitTesting(false)
                }
                SkinTouchLayer(layout: layout, state: touches, onMenu: onMenu, onKeyboard: onKeyboard)

                // An imported skin has no keyboard button: put one next
                // to its menu button.
                if showKeyboard, !layout.hasKeyboardButton, let menu = layout.menuFrame {
                    let sx = geo.size.width / layout.mappingSize.width
                    let sy = geo.size.height / layout.mappingSize.height
                    let rect = menu.applying(.init(scaleX: sx, y: sy))
                    let size: CGFloat = 38
                    let x = rect.minX - size / 2 - 10 < size ? rect.maxX + size / 2 + 10 : rect.minX - size / 2 - 10
                    KeyboardButton(action: onKeyboard)
                        .position(x: x, y: rect.midY)
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func artwork(size: CGSize) -> some View {
        switch skin.source {
        case .builtIn(let style):
            BuiltInSkinArt(style: style, layout: layout, pressed: touches.pressed, held: touches.held,
                           knobs: touches.knobs,
                           layer: .shell)
        case .imported:
            ZStack(alignment: .topLeading) {
                if let url = layout.artwork, let image = SkinArtwork.image(url, size: size) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                }
                // Imported art is flat: show presses with a soft glow.
                let sx = size.width / layout.mappingSize.width
                let sy = size.height / layout.mappingSize.height
                ForEach(Array(touches.pressed), id: \.self) { index in
                    if index < layout.items.count {
                        let rect = layout.items[index].frame.applying(.init(scaleX: sx, y: sy))
                        Ellipse()
                            .fill(.white.opacity(0.28))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
        }
    }
}

/// The whole rect, minus a hole (filled even-odd).
struct HoleShape: Shape {
    let hole: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if !hole.isEmpty { path.addRect(hole) }
        return path
    }
}

/// The keyboard button outside a skin's own art.
struct KeyboardButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.controlLabel)
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .emberGlass(Theme.controlGlass.interactive(), in: Circle())
        .accessibilityLabel("Teclado")
    }
}
