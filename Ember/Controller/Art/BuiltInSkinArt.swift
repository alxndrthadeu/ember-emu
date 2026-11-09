import SwiftUI
import UIKit

/// Which part of a built-in skin to draw: the shell (body, frame,
/// grille), which the game picture cuts through, and the controls,
/// which stay visible over it.
enum BuiltInLayer {
    case all, shell, controls
}

/// Draws a built-in skin's artwork for one layout, scaled to the view.
struct BuiltInSkinArt: View {
    let style: BuiltInStyle
    let layout: SkinLayout
    /// Indices of items being pressed right now.
    let pressed: Set<Int>
    /// The directions held on a d-pad or stick item, by item index.
    let held: [Int: Set<GameKey>]
    /// Where each stick's knob sits, -1 to 1 on each axis.
    var knobs: [Int: CGPoint] = [:]
    var layer: BuiltInLayer = .all

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / layout.mappingSize.width
            let sy = geo.size.height / layout.mappingSize.height
            let isPortrait = layout.mappingSize.height > layout.mappingSize.width

            ZStack(alignment: .topLeading) {
                if layer != .controls {
                    background(isPortrait: isPortrait)
                }

                // Book posture: the game's page reads as a screen of its
                // own, like a handheld with two screens.
                if layer != .controls, !isPortrait, let fold = layout.fold {
                    gamePage(width: fold * sx - 1, height: geo.size.height)
                }

                if layer != .controls, let screen = layout.screen {
                    // Tela cheia gets the thin frame, also when a wide screen
                    // (an open iPhone Duo) keeps the picture off the edges.
                    let thin = layout.fold != nil
                        || (isPortrait && (screen.minX <= BuiltInSkins.thinBezel + 1
                                           || SkinStore.shared.portraitFullWidth))
                    bezel(screen.applying(.init(scaleX: sx, y: sy)), isPortrait: isPortrait,
                          thin: thin ? BuiltInSkins.thinBezel * sx : nil)
                }

                ForEach(Array(layout.items.enumerated()).filter { _ in layer != .shell }, id: \.offset) { index, item in
                    let rect = item.frame.applying(.init(scaleX: sx, y: sy))
                    control(item, index: index, size: rect.size)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }

                if layer != .controls, let fold = layout.fold {
                    crease(at: fold, isPortrait: isPortrait, size: geo.size, sx: sx, sy: sy)
                }

                if layer != .controls && style == .ember && isPortrait && layout.fold == nil {
                    grille
                        .position(x: geo.size.width - 64 * sx, y: geo.size.height - 108 * sy)
                }
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    // MARK: Body

    @ViewBuilder
    private func background(isPortrait: Bool) -> some View {
        switch style {
        case .ember:
            LinearGradient(colors: [Color(hex: 0xF7A04B), Color(hex: 0xEE6A2A), Color(hex: 0xE05A24)],
                           startPoint: .top, endPoint: .bottom)
                .overlay(
                    // A soft shine across the shell.
                    LinearGradient(colors: [.white.opacity(0.18), .clear],
                                   startPoint: .topLeading, endPoint: .center))
        case .glass:
            Theme.controllerBackground
        }
    }

    /// `thin`: the frame width in Tela cheia (no logo strip).
    @ViewBuilder
    private func bezel(_ screen: CGRect, isPortrait: Bool, thin: CGFloat? = nil) -> some View {
        if style == .ember {
            let pad: CGFloat = thin ?? 12
            let bottom: CGFloat = thin ?? (isPortrait ? 30 : 12)
            RoundedRectangle(cornerRadius: thin == nil ? 22 : 10, style: .continuous)
                .fill(Color(hex: 0x2B211C))
                .overlay(alignment: .bottom) {
                    if isPortrait && thin == nil {
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: 0xF7B538))
                            Text("ember")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(hex: 0xF4E9D8).opacity(0.7))
                        }
                        .padding(.bottom, 8)
                    }
                }
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .frame(width: screen.width + pad * 2, height: screen.height + pad + bottom)
                .position(x: screen.midX, y: screen.midY + (bottom - pad) / 2)
            Rectangle()
                .fill(.black)
                .frame(width: screen.width, height: screen.height)
                .position(x: screen.midX, y: screen.midY)
        }
    }

    private func gamePage(width: CGFloat, height: CGFloat) -> some View {
        Theme.controllerBackground
            .frame(width: width, height: height)
            .overlay(alignment: .bottom) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0xF7B538))
                    Text("ember")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0xF4E9D8).opacity(0.6))
                }
                .padding(.bottom, 22)
            }
            .position(x: width / 2, y: height / 2)
    }

    /// A soft groove where an iPhone Duo folds, so the two halves read
    /// as two parts of one handheld.
    private func crease(at fold: CGFloat, isPortrait: Bool, size: CGSize, sx: CGFloat, sy: CGFloat) -> some View {
        let dark = style == .ember ? Color(hex: 0xB9481C) : Color.white.opacity(0.08)
        let light = style == .ember ? Color.white.opacity(0.22) : Color.black.opacity(0.4)
        return Group {
            if isPortrait {
                VStack(spacing: 0) {
                    Rectangle().fill(dark).frame(height: 1.5)
                    Rectangle().fill(light).frame(height: 1)
                }
                .frame(width: size.width)
                .position(x: size.width / 2, y: fold * sy)
            } else {
                HStack(spacing: 0) {
                    Rectangle().fill(dark).frame(width: 1.5)
                    Rectangle().fill(light).frame(width: 1)
                }
                .frame(height: size.height)
                .position(x: fold * sx, y: size.height / 2)
            }
        }
    }

    private var grille: some View {
        VStack(spacing: 7) {
            ForEach(0..<4) { _ in
                HStack(spacing: 7) {
                    ForEach(0..<4) { _ in
                        Circle().fill(Color(hex: 0xB9481C)).frame(width: 5, height: 5)
                    }
                }
            }
        }
        .rotationEffect(.degrees(-20))
    }

    // MARK: Controls

    @ViewBuilder
    private func control(_ item: SkinItem, index: Int, size: CGSize) -> some View {
        let isPressed = pressed.contains(index)
        switch item.kind {
        case .dpad:
            dpad(held: held[index] ?? [], size: size)
        case .stick:
            stick(knob: knobs[index] ?? .zero, active: pressed.contains(index), size: size)
        case .button:
            switch item.inputs.first {
            case .key(.confirm): roundButton("A", pressed: isPressed)
            case .key(.back): roundButton("B", pressed: isPressed)
            case .key(.x): roundButton("X", pressed: isPressed)
            case .key(.y): roundButton("Y", pressed: isPressed)
            case .key(.l): shoulder("L", pressed: isPressed, leading: true)
            case .key(.r): shoulder("R", pressed: isPressed, leading: false)
            case .key(.l2): shoulder("L2", pressed: isPressed, leading: true)
            case .key(.r2): shoulder("R2", pressed: isPressed, leading: false)
            case .key(.start): pill("START", pressed: isPressed)
            case .key(.select): pill("SELECT", pressed: isPressed)
            case .menu: gear(pressed: isPressed)
            case .keyboard: keyboardKey(pressed: isPressed)
            case .swapScreens: spareScreen(pressed: isPressed)
            default: EmptyView()
            }
        }
    }

    private var ink: Color { style == .ember ? Color(hex: 0x2B211C) : .clear }
    private var label: Color { Color(hex: 0xF4E9D8).opacity(0.9) }

    @ViewBuilder
    private func surface<S: Shape>(_ shape: S, pressed: Bool, fill: Color) -> some View {
        switch style {
        case .ember:
            Group {
                if #available(iOS 18, *), !EmberCompat.forceLegacy {
                    shape.fill(pressed ? fill.mix(with: .black, by: 0.3) : fill)
                } else {
                    // iOS 17 has no Color.mix: darken with a layer on top.
                    shape.fill(fill)
                        .overlay(shape.fill(Color.black.opacity(pressed ? 0.3 : 0)))
                }
            }
            .shadow(color: .black.opacity(pressed ? 0.1 : 0.3), radius: pressed ? 1 : 3, y: pressed ? 1 : 3)
        case .glass:
            shape.fill(.clear)
                .emberGlass(pressed ? Theme.controlGlassPressed : Theme.controlGlass, in: shape)
        }
    }

    private func roundButton(_ title: String, pressed: Bool) -> some View {
        ZStack {
            surface(Circle(), pressed: pressed, fill: Color(hex: 0x3A2F28))
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(label)
        }
        .scaleEffect(pressed ? 0.94 : 1)
    }

    private func shoulder(_ title: String, pressed: Bool, leading: Bool) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: leading ? 0 : 18, bottomLeadingRadius: leading ? 0 : 18,
            bottomTrailingRadius: leading ? 18 : 0, topTrailingRadius: leading ? 18 : 0,
            style: .continuous)
        return ZStack {
            if style == .ember {
                surface(shape, pressed: pressed, fill: Color(hex: 0xC8501E))
            } else {
                surface(Capsule(), pressed: pressed, fill: .clear)
            }
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(style == .ember ? Color(hex: 0xF4E9D8) : label)
        }
    }

    private func pill(_ title: String, pressed: Bool) -> some View {
        ZStack {
            surface(Capsule(), pressed: pressed, fill: Color(hex: 0x2B211C))
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(label)
        }
    }

    private func gear(pressed: Bool) -> some View {
        ZStack {
            surface(Circle(), pressed: pressed, fill: Color(hex: 0x2B211C))
            Image(systemName: "gearshape.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(label)
        }
    }

    /// The free screen of the DS layout: dark, with a hint to bring
    /// the game over.
    private func spareScreen(pressed: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.controllerBackground.opacity(pressed ? 0.8 : 1))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(hex: 0x2B211C), lineWidth: 4)
            }
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: 0xF7B538).opacity(0.8))
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(label.opacity(0.5))
                }
            }
            .accessibilityLabel(Text("Trocar o jogo de tela"))
    }

    private func keyboardKey(pressed: Bool) -> some View {
        ZStack {
            surface(Circle(), pressed: pressed, fill: Color(hex: 0x2B211C))
            Image(systemName: "keyboard.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(label)
        }
    }

    /// An analog stick: a dark well and a knob that follows the thumb.
    private func stick(knob: CGPoint, active: Bool, size: CGSize) -> some View {
        let side = min(size.width, size.height)
        let knobSize = side * 0.5
        let travel = (side - knobSize) / 2
        return ZStack {
            surface(Circle(), pressed: false, fill: Color(hex: 0x2B211C))
            Circle()
                .strokeBorder(label.opacity(0.12), lineWidth: 2)
                .padding(side * 0.08)
            ZStack {
                surface(Circle(), pressed: active, fill: Color(hex: 0x3A2F28))
                Circle()
                    .strokeBorder(active ? Theme.highlight.opacity(0.8) : label.opacity(0.15), lineWidth: 2)
            }
            .frame(width: knobSize, height: knobSize)
            .offset(x: knob.x * travel, y: knob.y * travel)
        }
        .frame(width: side, height: side)
    }

    private func dpad(held: Set<GameKey>, size: CGSize) -> some View {
        let arm = min(size.width, size.height) * 0.36
        let cross = PlusShape(arm: arm, radius: style == .ember ? 8 : 14)
        return ZStack {
            surface(cross, pressed: false, fill: Color(hex: 0x2B211C))
            if style == .ember {
                Circle().fill(Color(hex: 0x3A2F28)).frame(width: arm * 0.55, height: arm * 0.55)
            }
            ForEach([GameKey.up, .down, .left, .right], id: \.self) { key in
                Image(systemName: "arrowtriangle.\(arrowName(key)).fill")
                    .font(.system(size: 13))
                    .foregroundStyle(held.contains(key) ? Theme.highlight : label.opacity(0.7))
                    .offset(arrowOffset(key, size: size))
            }
        }
    }

    private func arrowName(_ key: GameKey) -> String {
        switch key {
        case .up: "up"
        case .down: "down"
        case .left: "left"
        default: "right"
        }
    }

    private func arrowOffset(_ key: GameKey, size: CGSize) -> CGSize {
        let d = min(size.width, size.height) * 0.34
        switch key {
        case .up: return CGSize(width: 0, height: -d)
        case .down: return CGSize(width: 0, height: d)
        case .left: return CGSize(width: -d, height: 0)
        default: return CGSize(width: d, height: 0)
        }
    }
}

/// A plus sign with rounded arm ends, centered in its rect.
struct PlusShape: Shape {
    let arm: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let h = CGRect(x: rect.minX, y: rect.midY - arm / 2, width: rect.width, height: arm)
        let v = CGRect(x: rect.midX - arm / 2, y: rect.minY, width: arm, height: rect.height)
        return Path(roundedRect: h, cornerRadius: radius)
            .union(Path(roundedRect: v, cornerRadius: radius))
    }
}
