import SwiftUI
import UIKit

/// The phone layouts every built-in skin starts from, in Delta's point
/// space (414 × 896 portrait, 896 × 414 landscape), and how they adapt
/// to a game (keyboard button, the game's own proportion).
extension BuiltInSkins {
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

    /// The frame width around the screen in Tela cheia.
    static let thinBezel: CGFloat = 6

    static let directions: [SkinInput] = [.key(.up), .key(.down), .key(.left), .key(.right)]

    static func button(_ input: SkinInput, _ x: CGFloat, _ y: CGFloat,
                               _ width: CGFloat, _ height: CGFloat) -> SkinItem {
        SkinItem(kind: .button, inputs: [input], frame: CGRect(x: x, y: y, width: width, height: height))
    }
}
