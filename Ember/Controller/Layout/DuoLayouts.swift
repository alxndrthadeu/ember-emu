import SwiftUI
import UIKit

/// Layouts for screens wider than a phone's: an open iPhone Duo. They
/// take a phone layout and redraw it for the Duo's proportions and
/// postures (portrait DS, landscape console, half-folded book).
extension BuiltInSkins {
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
        // Below the front camera, which sits in the top corner of the
        // Duo's inner screen.
        let cameraClear: CGFloat = 60
        let upper = fit(ratio, in: CGRect(x: 8, y: cameraClear, width: width - 16,
                                          height: fold - gap / 2 - 8 - cameraClear))

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
            // Shoulders near the top corners, below the front camera (it
            // sits in a top corner of the inner screen).
            case .key(.l): place(0, 64, side - 10, 40)
            case .key(.r): place(right + 10, 64, side - 10, 40)
            // Leaves room under L and R for L2 and R2 (Moderno).
            case .menu: place(side / 2 - 20, 152, 40, 40)
            case .keyboard: place(right + side / 2 - 20, 152, 40, 40)
            // Where the thumbs rest: a little below the middle.
            case .key(.up): place(6, 204, side - 12, side - 12)
            case .key(.confirm): place(width - 64, 204, 58, 58)
            case .key(.back): place(right + 4, 266, 58, 58)
            case .key(.select): place(side / 2 - 38, 356, 76, 28)
            case .key(.start): place(right + side / 2 - 38, 356, 76, 28)
            default: break
            }
            return item
        }
        return copy
    }

    static func fit(_ ratio: CGFloat, in area: CGRect) -> CGRect {
        var w = area.width
        var h = w / ratio
        if h > area.height {
            h = area.height
            w = h * ratio
        }
        return CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
    }
}
