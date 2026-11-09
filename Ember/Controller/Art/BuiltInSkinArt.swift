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

            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }

    // MARK: Body

    private var palette: ShellPalette { style.palette }

    @ViewBuilder
    private func background(isPortrait: Bool) -> some View {
        if style.isShell {
            ZStack {
                // Tinted plastic, lighter where the light comes in.
                LinearGradient(colors: [palette.light, palette.base, palette.deep],
                               startPoint: .top, endPoint: .bottom)
                // The board and parts seen through the shell.
                ShellInternals(palette: palette, mapping: layout.mappingSize, screen: layout.screen)
                // Haze and shine of clear plastic.
                RadialGradient(colors: [.white.opacity(0.22), .clear],
                               center: UnitPoint(x: 0.2, y: 0.05), startRadius: 0, endRadius: 520)
                LinearGradient(colors: [.clear, .black.opacity(0.18)], startPoint: .center, endPoint: .bottom)
            }
            .overlay {
                // The molded rim.
                Rectangle()
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05), .black.opacity(0.25)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 3)
            }
        } else {
            Theme.controllerBackground
        }
    }

    /// `thin`: the frame width in Tela cheia (no logo strip).
    @ViewBuilder
    private func bezel(_ screen: CGRect, isPortrait: Bool, thin: CGFloat? = nil) -> some View {
        if style.isShell {
            let pad: CGFloat = thin ?? 12
            let bottom: CGFloat = thin ?? (isPortrait ? 30 : 12)
            let shape = RoundedRectangle(cornerRadius: thin == nil ? 22 : 12, style: .continuous)
            shape
                .fill(LinearGradient(colors: [Color(hex: 0x2A2224), Color(hex: 0x161113)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .clear, .black.opacity(0.4)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                }
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
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
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
        let dark = style.isShell ? palette.deep.opacity(0.9) : Color.white.opacity(0.08)
        let light = style.isShell ? Color.white.opacity(0.22) : Color.black.opacity(0.4)
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

    private var label: Color { Color(hex: 0xF4E9D8).opacity(0.9) }

    /// A molded button: charcoal plastic with a soft top light, a rim and
    /// a shadow under it; pressed, it sinks.
    private func dome<S: Shape>(_ shape: S, pressed: Bool) -> some View {
        shape
            .fill(LinearGradient(colors: [palette.buttonLight, palette.button],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                shape.fill(RadialGradient(colors: [.white.opacity(pressed ? 0.04 : 0.2), .clear],
                                          center: UnitPoint(x: 0.35, y: 0.2), startRadius: 0, endRadius: 60))
            }
            .overlay {
                shape.stroke(LinearGradient(colors: [.white.opacity(0.2), .black.opacity(0.35)],
                                            startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
            }
            .shadow(color: .black.opacity(pressed ? 0.15 : 0.42), radius: pressed ? 1 : 4, y: pressed ? 1 : 3)
            .scaleEffect(pressed ? 0.95 : 1)
    }

    /// The recess a button sits in, molded into the shell.
    private func well<S: Shape>(_ shape: S) -> some View {
        shape
            .fill(palette.deep.opacity(0.45))
            .overlay {
                shape.stroke(LinearGradient(colors: [.black.opacity(0.35), .white.opacity(0.28)],
                                            startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
            }
    }

    @ViewBuilder
    private func surface<S: Shape>(_ shape: S, pressed: Bool, fill: Color) -> some View {
        switch style {
        case .ember, .brasa, .musgo, .fume:
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

    @ViewBuilder
    private func roundButton(_ title: String, pressed: Bool) -> some View {
        if style.isShell {
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                ZStack {
                    well(Circle()).frame(width: side * 1.14, height: side * 1.14)
                    dome(Circle(), pressed: pressed).frame(width: side, height: side)
                    Text(title)
                        .font(.system(size: side * 0.36, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.label)
                        .scaleEffect(pressed ? 0.95 : 1)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        } else {
            ZStack {
                surface(Circle(), pressed: pressed, fill: Color(hex: 0x3A2F28))
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(label)
            }
            .scaleEffect(pressed ? 0.94 : 1)
        }
    }

    @ViewBuilder
    private func shoulder(_ title: String, pressed: Bool, leading: Bool) -> some View {
        if style.isShell {
            GeometryReader { geo in
                ZStack {
                    dome(Capsule(), pressed: pressed)
                    Text(title)
                        .font(.system(size: min(17, geo.size.height * 0.42), weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.label)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            }
        } else {
            ZStack {
                surface(Capsule(), pressed: pressed, fill: .clear)
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(label)
            }
        }
    }

    @ViewBuilder
    private func pill(_ title: String, pressed: Bool) -> some View {
        if style.isShell {
            ZStack {
                dome(Capsule(), pressed: pressed)
                    .padding(.vertical, 3)
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(palette.label.opacity(0.8))
            }
        } else {
            ZStack {
                surface(Capsule(), pressed: pressed, fill: Color(hex: 0x2B211C))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(label)
            }
        }
    }

    private func gear(pressed: Bool) -> some View {
        smallRound(icon: "gearshape.fill", size: 17, pressed: pressed)
    }

    @ViewBuilder
    private func smallRound(icon: String, size: CGFloat, pressed: Bool) -> some View {
        if style.isShell {
            ZStack {
                dome(Circle(), pressed: pressed)
                Image(systemName: icon)
                    .font(.system(size: size - 1, weight: .semibold))
                    .foregroundStyle(palette.label.opacity(0.85))
            }
        } else {
            ZStack {
                surface(Circle(), pressed: pressed, fill: Color(hex: 0x2B211C))
                Image(systemName: icon)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(label)
            }
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
        smallRound(icon: "keyboard.fill", size: 15, pressed: pressed)
    }

    /// An analog stick: a recess and a knob with grip rings that follows
    /// the thumb.
    private func stick(knob: CGPoint, active: Bool, size: CGSize) -> some View {
        let side = min(size.width, size.height)
        let knobSize = side * 0.52
        let travel = (side - knobSize) / 2
        return ZStack {
            if style.isShell {
                well(Circle())
                Circle()
                    .stroke(palette.deep.opacity(0.5), lineWidth: 1)
                    .padding(side * 0.1)
                ZStack {
                    dome(Circle(), pressed: active)
                    ForEach([0.62, 0.36], id: \.self) { ratio in
                        Circle()
                            .stroke(Color.black.opacity(0.28), lineWidth: 1.5)
                            .frame(width: knobSize * ratio, height: knobSize * ratio)
                    }
                    if active {
                        Circle().stroke(Theme.highlight.opacity(0.7), lineWidth: 2)
                    }
                }
                .frame(width: knobSize, height: knobSize)
                .offset(x: knob.x * travel, y: knob.y * travel)
            } else {
                surface(Circle(), pressed: false, fill: Color(hex: 0x2B211C))
                ZStack {
                    surface(Circle(), pressed: active, fill: Color(hex: 0x3A2F28))
                    Circle()
                        .strokeBorder(active ? Theme.highlight.opacity(0.8) : label.opacity(0.15), lineWidth: 2)
                }
                .frame(width: knobSize, height: knobSize)
                .offset(x: knob.x * travel, y: knob.y * travel)
            }
        }
        .frame(width: side, height: side)
    }

    @ViewBuilder
    private func dpad(held: Set<GameKey>, size: CGSize) -> some View {
        let side = min(size.width, size.height)
        let arm = side * 0.34
        if style.isShell {
            let cross = PlusShape(arm: arm, radius: arm * 0.22)
            ZStack {
                // A round recess, the cross molded in it.
                well(Circle()).frame(width: side * 1.06, height: side * 1.06)
                dome(cross, pressed: false)
                    .frame(width: side * 0.86, height: side * 0.86)
                // A shallow dish in the middle.
                Circle()
                    .fill(LinearGradient(colors: [.black.opacity(0.35), .white.opacity(0.08)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: arm * 0.5, height: arm * 0.5)
                ForEach([GameKey.up, .down, .left, .right], id: \.self) { key in
                    let lit = held.contains(key)
                    Capsule()
                        .fill(lit ? Theme.highlight : palette.label.opacity(0.55))
                        .frame(width: key == .up || key == .down ? 2.5 : arm * 0.32,
                               height: key == .up || key == .down ? arm * 0.32 : 2.5)
                        .shadow(color: lit ? Theme.highlight.opacity(0.8) : .clear, radius: 4)
                        .offset(arrowOffset(key, size: CGSize(width: side * 0.86, height: side * 0.86)))
                }
            }
            .frame(width: size.width, height: size.height)
        } else {
            let cross = PlusShape(arm: side * 0.36, radius: 14)
            ZStack {
                surface(cross, pressed: false, fill: Color(hex: 0x2B211C))
                ForEach([GameKey.up, .down, .left, .right], id: \.self) { key in
                    Image(systemName: "arrowtriangle.\(arrowName(key)).fill")
                        .font(.system(size: 13))
                        .foregroundStyle(held.contains(key) ? Theme.highlight : label.opacity(0.7))
                        .offset(arrowOffset(key, size: size))
                }
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
