import SwiftUI
import UIKit

/// Controller types on built-in skins: any finished layout (phone or
/// Duo) gets the buttons its type adds.
extension BuiltInSkins {
    /// A built-in layout for the game's controller type, drawn from any
    /// of the layouts above: X and Y join A and B in a diamond, L2 and R2
    /// sit under L and R, and the D-pad becomes a stick (Moderno).
    static func typed(_ layout: SkinLayout, type: ControllerType) -> SkinLayout {
        guard type != .classic2 else { return layout }
        var copy = layout
        func index(_ input: SkinInput) -> Int? { copy.items.firstIndex { $0.inputs.first == input } }

        if let ai = index(.key(.confirm)), let bi = index(.key(.back)) {
            var cluster = copy.items[ai].frame.union(copy.items[bi].frame)
            var side = max(cluster.width, cluster.height) * 1.08
            // Stay off the game picture and inside the screen: a narrow
            // side column (Duo console layout) gets a smaller diamond.
            if let screen = copy.screen,
               cluster.maxY > screen.minY, cluster.minY < screen.maxY {
                let onRight = cluster.midX > screen.midX
                let room = onRight ? copy.mappingSize.width - screen.maxX - 8 : screen.minX - 8
                if room > 40, room < side { side = room }
                let center = CGPoint(x: onRight ? max(cluster.midX, screen.maxX + 4 + side / 2)
                                                : min(cluster.midX, screen.minX - 4 - side / 2),
                                     y: cluster.midY)
                let overlapsScreen = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
                    .intersects(screen)
                if overlapsScreen || room < side + 8 {
                    cluster = CGRect(x: center.x - cluster.width / 2, y: cluster.minY,
                                     width: cluster.width, height: cluster.height)
                }
            }
            side = min(side, copy.mappingSize.width - 8)
            let edge = copy.mappingSize.width - 4
            if cluster.midX + side / 2 > edge { cluster.origin.x -= cluster.midX + side / 2 - edge }
            let size = side * 0.4
            let reach = side / 2 - size / 2
            func spot(_ dx: CGFloat, _ dy: CGFloat) -> CGRect {
                CGRect(x: cluster.midX + dx - size / 2, y: cluster.midY + dy - size / 2, width: size, height: size)
            }
            copy.items[ai].frame = spot(reach, 0)
            copy.items[bi].frame = spot(0, reach)
            copy.items.append(button(.key(.x), spot(0, -reach)))
            copy.items.append(button(.key(.y), spot(-reach, 0)))
        }

        if type == .modern {
            if let di = copy.items.firstIndex(where: { $0.kind == .dpad }) {
                copy.items[di].kind = .stick
            }
            for (shoulder, second) in [(SkinInput.key(.l), SkinInput.key(.l2)), (.key(.r), .key(.r2))] {
                guard let si = index(shoulder) else { continue }
                let frame = copy.items[si].frame
                let leading = frame.midX < copy.mappingSize.width / 2
                let w = frame.width * 0.8, h = frame.height * 0.82
                var spot = CGRect(x: leading ? frame.minX : frame.maxX - w, y: frame.maxY + 6, width: w, height: h)
                let others = copy.items.map(\.frame)
                if others.contains(where: { $0.intersects(spot) }) || spot.maxY > copy.mappingSize.height {
                    // No room below: beside it, toward the middle.
                    let sw = frame.width * 0.62
                    spot = CGRect(x: leading ? frame.maxX + 6 : frame.minX - 6 - sw, y: frame.minY, width: sw, height: frame.height)
                }
                if !others.contains(where: { $0.intersects(spot) }) {
                    copy.items.append(button(second, spot))
                }
            }
        }
        return copy
    }

    static func button(_ input: SkinInput, _ frame: CGRect) -> SkinItem {
        SkinItem(kind: .button, inputs: [input], frame: frame)
    }
}
