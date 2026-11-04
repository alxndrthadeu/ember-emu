import SwiftUI
import UIKit

/// The art styles Ember draws itself.
enum BuiltInStyle: String, Hashable {
    /// The default: an orange handheld, in Ember's palette.
    case ember
    /// Liquid Glass buttons over a dark controller area.
    case glass
}

/// Ember's own skins. Both share one layout, in Delta's point space,
/// so their hit areas work exactly like an imported skin's.
enum BuiltInSkins {
    static let ember = Skin(id: "ember.laranja", name: String(localized: "Ember Laranja"),
                            source: .builtIn(.ember), portrait: portrait, landscape: landscape)
    static let glass = Skin(id: "ember.vidro", name: String(localized: "Vidro"),
                            source: .builtIn(.glass), portrait: portrait, landscape: landscape)
    static let all = [ember, glass]

    // MARK: Layouts

    static let portrait = SkinLayout(
        mappingSize: CGSize(width: 414, height: 896),
        artwork: nil,
        items: [
            button(.key(.l), 0, 404, 112, 44),
            // Gear and keyboard side by side; the keyboard shows only for
            // games that poll a PC keyboard, else the gear sits alone.
            button(.menu, 161, 406, 40, 40),
            button(.keyboard, 213, 406, 40, 40),
            button(.key(.r), 302, 404, 112, 44),
            SkinItem(kind: .dpad, inputs: directions, frame: CGRect(x: 30, y: 520, width: 156, height: 156),
                     extendedEdges: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)),
            button(.key(.confirm), 302, 516, 78, 78),
            button(.key(.back), 216, 588, 78, 78),
            button(.key(.select), 124, 742, 76, 28),
            button(.key(.start), 214, 742, 76, 28),
        ],
        screen: CGRect(x: 24, y: 72, width: 366, height: 274.5),
        extendedEdges: UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8),
        translucent: false)

    static let landscape = SkinLayout(
        mappingSize: CGSize(width: 896, height: 414),
        artwork: nil,
        items: [
            button(.key(.l), 0, 0, 150, 46),
            button(.key(.r), 746, 0, 150, 46),
            SkinItem(kind: .dpad, inputs: directions, frame: CGRect(x: 34, y: 140, width: 146, height: 146),
                     extendedEdges: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)),
            button(.key(.confirm), 790, 150, 74, 74),
            button(.key(.back), 712, 214, 74, 74),
            button(.key(.select), 44, 342, 66, 26),
            button(.key(.start), 120, 342, 66, 26),
            button(.menu, 790, 334, 40, 40),
            button(.keyboard, 738, 334, 40, 40),
        ],
        screen: CGRect(x: 208, y: 27, width: 480, height: 360),
        extendedEdges: UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8),
        translucent: true)

    /// A built-in layout for one game: without the keyboard button, the
    /// portrait gear moves back to the middle.
    static func adapted(_ layout: SkinLayout, keyboard: Bool) -> SkinLayout {
        guard !keyboard else { return layout }
        var copy = layout
        copy.items.removeAll { $0.inputs.contains(.keyboard) }
        if copy.mappingSize.height > copy.mappingSize.width,
           let index = copy.items.firstIndex(where: { $0.inputs.contains(.menu) }) {
            copy.items[index].frame.origin.x = (copy.mappingSize.width - copy.items[index].frame.width) / 2
        }
        return copy
    }

    private static let directions: [SkinInput] = [.key(.up), .key(.down), .key(.left), .key(.right)]

    private static func button(_ input: SkinInput, _ x: CGFloat, _ y: CGFloat,
                               _ width: CGFloat, _ height: CGFloat) -> SkinItem {
        SkinItem(kind: .button, inputs: [input], frame: CGRect(x: x, y: y, width: width, height: height))
    }
}

/// Draws a built-in skin's artwork for one layout, scaled to the view.
struct BuiltInSkinArt: View {
    let style: BuiltInStyle
    let layout: SkinLayout
    /// Indices of items being pressed right now.
    let pressed: Set<Int>
    /// The direction held on a d-pad item, by item index.
    let held: [Int: GameKey]

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / layout.mappingSize.width
            let sy = geo.size.height / layout.mappingSize.height
            let isPortrait = layout.mappingSize.height > layout.mappingSize.width

            ZStack(alignment: .topLeading) {
                background(isPortrait: isPortrait)

                if let screen = layout.screen {
                    bezel(screen.applying(.init(scaleX: sx, y: sy)), isPortrait: isPortrait)
                }

                ForEach(Array(layout.items.enumerated()), id: \.offset) { index, item in
                    let rect = item.frame.applying(.init(scaleX: sx, y: sy))
                    control(item, index: index, size: rect.size)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }

                if style == .ember && isPortrait {
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

    @ViewBuilder
    private func bezel(_ screen: CGRect, isPortrait: Bool) -> some View {
        if style == .ember {
            let pad: CGFloat = isPortrait ? 12 : 12
            let bottom: CGFloat = isPortrait ? 30 : 12
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: 0x2B211C))
                .overlay(alignment: .bottom) {
                    if isPortrait {
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
            dpad(held: held[index], size: size)
        case .button:
            switch item.inputs.first {
            case .key(.confirm): roundButton("A", pressed: isPressed)
            case .key(.back): roundButton("B", pressed: isPressed)
            case .key(.l): shoulder("L", pressed: isPressed, leading: true)
            case .key(.r): shoulder("R", pressed: isPressed, leading: false)
            case .key(.start): pill("START", pressed: isPressed)
            case .key(.select): pill("SELECT", pressed: isPressed)
            case .menu: gear(pressed: isPressed)
            case .keyboard: keyboardKey(pressed: isPressed)
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
            shape.fill(pressed ? fill.mix(with: .black, by: 0.3) : fill)
                .shadow(color: .black.opacity(pressed ? 0.1 : 0.3), radius: pressed ? 1 : 3, y: pressed ? 1 : 3)
        case .glass:
            shape.fill(.clear)
                .glassEffect(pressed ? Theme.controlGlassPressed : Theme.controlGlass, in: shape)
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

    private func keyboardKey(pressed: Bool) -> some View {
        ZStack {
            surface(Circle(), pressed: pressed, fill: Color(hex: 0x2B211C))
            Image(systemName: "keyboard.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(label)
        }
    }

    private func dpad(held: GameKey?, size: CGSize) -> some View {
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
                    .foregroundStyle(held == key ? Theme.highlight : label.opacity(0.7))
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
