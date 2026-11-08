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

    /// The portrait screen for this game: shaped like the game's own
    /// picture (no black bars inside the frame), either in a thin frame
    /// or across the full width under the Dynamic Island. Portrait
    /// width is the limit: RPG Maker games are wider than tall.
    static func fitted(_ layout: SkinLayout, aspect: CGFloat?, fullWidth: Bool) -> SkinLayout {
        guard layout.mappingSize.height > layout.mappingSize.width, layout.screen != nil else { return layout }
        let ratio = max(aspect ?? 4 / 3, 0.5)
        let width = layout.mappingSize.width
        // Keep clear of L/R and the gear row (y 404 on a phone), leaving
        // room for the logo strip in Clássica.
        let controlsTop = layout.items.map(\.frame.minY).min() ?? 404
        let bottomLimit: CGFloat = controlsTop - (fullWidth ? 12 : 34)
        var screen: CGRect
        if fullWidth {
            // Tela cheia: nearly edge to edge, in a thin frame.
            let w = width - 2 * thinBezel
            screen = CGRect(x: thinBezel, y: 64, width: w, height: w / ratio)
        } else {
            // Clássica: the original frame with the logo under the screen.
            screen = CGRect(x: 24, y: 72, width: 366, height: 366 / ratio)
        }
        if screen.maxY > bottomLimit {
            let h = bottomLimit - screen.minY
            let w = h * ratio
            screen = CGRect(x: (width - w) / 2, y: screen.minY, width: w, height: h)
        }
        var copy = layout
        copy.screen = screen
        return copy
    }

    /// Height / width below which a portrait screen counts as wide (an
    /// open iPhone Duo is about 1.46; phones are about 2.17).
    static let wideBelow: CGFloat = 1.75

    /// The portrait layout redrawn for a wide screen: the same point
    /// width (414), a height in the screen's own proportion, and the
    /// controls kept at the bottom, scaled evenly (shapes stay round)
    /// so they take at most about half the height. `fitted` then gives
    /// the game the space above them.
    static func reshaped(_ layout: SkinLayout, viewAspect: CGFloat) -> SkinLayout {
        let width = layout.mappingSize.width
        let height = (width * viewAspect).rounded()
        guard height < layout.mappingSize.height, !layout.items.isEmpty else { return layout }
        let bandTop = layout.items.map(\.frame.minY).min()!
        let bandBottom = layout.items.map(\.frame.maxY).max()!
        let band = bandBottom - bandTop
        let scale = min(1, height * 0.5 / (band + 24))
        let newTop = height - 20 - band * scale
        var copy = layout
        copy.mappingSize = CGSize(width: width, height: height)
        copy.items = layout.items.map { item in
            var item = item
            let f = item.frame
            item.frame = CGRect(x: width / 2 + (f.minX - width / 2) * scale,
                                y: newTop + (f.minY - bandTop) * scale,
                                width: f.width * scale, height: f.height * scale)
            return item
        }
        return copy
    }

    /// The landscape layout for a screen less wide than a phone's: the
    /// same height (414), a width in the screen's proportion, the
    /// right-hand controls following the right edge, and the game
    /// centered in its own shape (the controls float over it, as in
    /// any landscape layout).
    static func reshapedLandscape(_ layout: SkinLayout, viewAspect: CGFloat, gameAspect: CGFloat?) -> SkinLayout {
        let height = layout.mappingSize.height
        let oldWidth = layout.mappingSize.width
        let width = (height * viewAspect).rounded()
        guard width < oldWidth else { return layout }
        var copy = layout
        copy.mappingSize = CGSize(width: width, height: height)
        copy.items = layout.items.map { item in
            var item = item
            if item.frame.midX > oldWidth / 2 { item.frame.origin.x += width - oldWidth }
            return item
        }
        if layout.screen != nil {
            let ratio = max(gameAspect ?? 4 / 3, 0.5)
            var h = height - 54
            var w = h * ratio
            if w > width - 16 {
                w = width - 16
                h = w / ratio
            }
            copy.screen = CGRect(x: (width - w) / 2, y: (height - h) / 2, width: w, height: h)
        }
        return copy
    }

    // MARK: iPhone Duo, split like a handheld with two screens

    /// The gap kept clear around the fold (mapping points): the crease
    /// is curved and hard to read or tap. Wider when the Duo is half
    /// folded, where the halves meet at an angle.
    static func foldGap(partiallyOpen: Bool) -> CGFloat { partiallyOpen ? 40 : 26 }

    /// Portrait, unfolded (the fold runs across): a Nintendo DS. Each
    /// half is close to 4:3, like a DS screen. The game fills the top
    /// half; the bottom half holds the controller around a 4:3 window,
    /// where the player can move the game (`gameBelow`). The free
    /// screen is a `.swapScreens` item: tapping it moves the game there.
    static func splitPortrait(_ layout: SkinLayout, viewAspect: CGFloat, gameAspect: CGFloat?,
                              gap: CGFloat, gameBelow: Bool = false) -> SkinLayout {
        let width = layout.mappingSize.width
        let height = (width * viewAspect).rounded()
        let fold = (height / 2).rounded()
        var copy = layout
        copy.mappingSize = CGSize(width: width, height: height)
        copy.fold = fold
        copy.translucent = false

        let ratio = max(gameAspect ?? 4 / 3, 0.5)
        // Top half: the whole half is the screen.
        let upper = fit(ratio, in: CGRect(x: 8, y: 14, width: width - 16, height: fold - gap / 2 - 8 - 14))

        // Bottom half, drawn for about 250 points of height and squeezed
        // evenly if there is less.
        let top = fold + gap / 2
        let room = height - 14 - top
        let squeeze = min(1, room / 250)
        func y(_ value: CGFloat) -> CGFloat { top + value * squeeze }
        let windowWidth: CGFloat = 176 * squeeze
        let window = fit(ratio, in: CGRect(x: (width - windowWidth) / 2, y: y(48),
                                           width: windowWidth, height: windowWidth * 3 / 4))

        copy.screen = gameBelow ? window : upper
        copy.items = layout.items.map { item in
            var item = item
            func place(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) {
                item.frame = CGRect(x: x, y: y(top), width: w, height: h)
            }
            let d = 104 * squeeze, ab = 54 * squeeze
            switch item.inputs.first {
            case .key(.l): place(0, 4, 100, 36)
            case .key(.r): place(width - 100, 4, 100, 36)
            case .key(.up): place(10, 62, d, d)
            case .key(.confirm): place(width - ab - 8, 56, ab, ab)
            case .key(.back): place(width - 2 * ab - 4, 110, ab, ab)
            case .menu: place(18, 196, 40, 40)
            case .keyboard: place(width - 58, 196, 40, 40)
            case .key(.select): place(width / 2 - 80, 204, 72, 26)
            case .key(.start): place(width / 2 + 8, 204, 72, 26)
            default: break
            }
            return item
        }
        // The free screen: tap to bring the game there.
        copy.items.append(SkinItem(kind: .button, inputs: [.swapScreens],
                                   frame: gameBelow ? upper : window))
        return copy
    }

    /// Landscape, unfolded (the fold runs down the middle, like a book):
    /// the game on the left page, the controller on the right page.
    static func splitLandscape(_ layout: SkinLayout, viewAspect: CGFloat, gameAspect: CGFloat?,
                               gap: CGFloat) -> SkinLayout {
        let height = layout.mappingSize.height
        let width = (height * viewAspect).rounded()
        let fold = (width / 2).rounded()
        var copy = layout
        copy.mappingSize = CGSize(width: width, height: height)
        copy.fold = fold
        copy.translucent = false

        let ratio = max(gameAspect ?? 4 / 3, 0.5)
        let area = CGRect(x: 18, y: 16, width: fold - gap / 2 - 10 - 18, height: height - 32)
        copy.screen = fit(ratio, in: area)

        // The right page is about as wide as a phone held upright: the
        // same controller, d-pad on the left, A and B on the right.
        let left = fold + gap / 2
        let page = width - left
        let unit = min(1, page / 300)
        copy.items = layout.items.map { item in
            var item = item
            func place(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
                item.frame = CGRect(x: left + x * unit, y: y, width: w * unit, height: h * unit)
            }
            let hasKeyboard = layout.hasKeyboardButton
            switch item.inputs.first {
            case .key(.l): place(0, 26, 88, 40)
            case .key(.r): place(page / unit - 88, 26, 88, 40)
            case .menu: place(hasKeyboard ? page / unit / 2 - 46 : page / unit / 2 - 20, 26, 40, 40)
            case .keyboard: place(page / unit / 2 + 6, 26, 40, 40)
            case .key(.up): place(8, 130, 124, 124)
            case .key(.confirm): place(page / unit - 80, 126, 70, 70)
            case .key(.back): place(page / unit - 150, 192, 70, 70)
            case .key(.select): place(page / unit / 2 - 76, 340, 70, 26)
            case .key(.start): place(page / unit / 2 + 6, 340, 70, 26)
            default: break
            }
            return item
        }
        return copy
    }

    /// Landscape, lying flat: held like a handheld console (Switch Lite,
    /// PS Vita). Both hands grip the sides, so the controls sit in a
    /// column on each side at thumb height and the game gets the middle,
    /// with nothing over it.
    static func handheldLandscape(_ layout: SkinLayout, viewAspect: CGFloat, gameAspect: CGFloat?) -> SkinLayout {
        let height = layout.mappingSize.height
        let width = (height * viewAspect).rounded()
        let side: CGFloat = 116
        var copy = layout
        copy.mappingSize = CGSize(width: width, height: height)
        copy.translucent = false
        copy.fold = nil

        let ratio = max(gameAspect ?? 4 / 3, 0.5)
        copy.screen = fit(ratio, in: CGRect(x: side + 8, y: 14, width: width - 2 * side - 16, height: height - 28))

        let right = width - side
        copy.items = layout.items.map { item in
            var item = item
            func place(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
                item.frame = CGRect(x: x, y: y, width: w, height: h)
            }
            switch item.inputs.first {
            // Shoulders at the top corners, flat against the edge.
            case .key(.l): place(0, 14, side - 10, 40)
            case .key(.r): place(right + 10, 14, side - 10, 40)
            case .menu: place(side / 2 - 20, 74, 40, 40)
            case .keyboard: place(right + side / 2 - 20, 74, 40, 40)
            // Where the thumbs rest: a little below the middle.
            case .key(.up): place(6, 176, side - 12, side - 12)
            case .key(.confirm): place(width - 64, 170, 58, 58)
            case .key(.back): place(right + 4, 232, 58, 58)
            case .key(.select): place(side / 2 - 38, 356, 76, 28)
            case .key(.start): place(right + side / 2 - 38, 356, 76, 28)
            default: break
            }
            return item
        }
        return copy
    }

    private static func fit(_ ratio: CGFloat, in area: CGRect) -> CGRect {
        var w = area.width
        var h = w / ratio
        if h > area.height {
            h = area.height
            w = h * ratio
        }
        return CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
    }

    /// The frame width around the screen in Tela cheia.
    static let thinBezel: CGFloat = 6

    private static let directions: [SkinInput] = [.key(.up), .key(.down), .key(.left), .key(.right)]

    private static func button(_ input: SkinInput, _ x: CGFloat, _ y: CGFloat,
                               _ width: CGFloat, _ height: CGFloat) -> SkinItem {
        SkinItem(kind: .button, inputs: [input], frame: CGRect(x: x, y: y, width: width, height: height))
    }
}

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
    /// The direction held on a d-pad item, by item index.
    let held: [Int: GameKey]
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
