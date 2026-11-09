import SwiftUI
import UIKit

/// Draws an imported skin for one layout: its artwork as the artist made
/// it, or, recomposed (SkinRecomposer), a background in its colors with
/// each button's own picture. Presses show as the button sinking (own
/// pictures) or a soft glow (buttons painted into the artwork).
struct ImportedSkinArt: View {
    let layout: SkinLayout
    var pressed: Set<Int> = []
    var knobs: [Int: CGPoint] = [:]

    var body: some View {
        GeometryReader { geo in
            let sx = geo.size.width / layout.mappingSize.width
            let sy = geo.size.height / layout.mappingSize.height
            let scale = CGAffineTransform(scaleX: sx, y: sy)
            ZStack(alignment: .topLeading) {
                if let backdrop = layout.backdrop {
                    LinearGradient(colors: [Color(backdrop.top), Color(backdrop.bottom)],
                                   startPoint: .top, endPoint: .bottom)
                }
                if let url = layout.artwork {
                    let frame = (layout.artworkFrame ?? CGRect(origin: .zero, size: layout.mappingSize)).applying(scale)
                    if let image = SkinArtwork.image(url, size: frame.size) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                } else if let backdrop = layout.backdrop, let screen = layout.screen?.applying(scale) {
                    // Recomposed: a plain frame around the game, in the shell's dark tone.
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(backdrop.bezel))
                        .frame(width: screen.width + 14, height: screen.height + 14)
                        .position(x: screen.midX, y: screen.midY)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                }

                ForEach(Array(layout.items.enumerated()), id: \.offset) { index, item in
                    let rect = item.frame.applying(scale)
                    piece(item, index: index, size: rect.size)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func piece(_ item: SkinItem, index: Int, size: CGSize) -> some View {
        let isPressed = pressed.contains(index)
        if let sprite = item.sprite, let image = SkinArtwork.image(sprite, size: size) {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .brightness(isPressed && item.kind == .button ? -0.18 : 0)
                    .scaleEffect(isPressed && item.kind == .button ? 0.94 : 1)
                if item.kind == .stick { knob(item, index: index, size: size) }
            }
        } else if item.kind == .stick, item.thumb != nil {
            knob(item, index: index, size: size)
        } else if layout.backdrop != nil && layout.artwork == nil {
            // Recomposed, and the skin has no picture of this one.
            PlainSkinButton(item: item, pressed: isPressed)
        } else if isPressed {
            // Painted into the artwork: a soft glow over it.
            Ellipse().fill(.white.opacity(0.28))
        }
    }

    @ViewBuilder
    private func knob(_ item: SkinItem, index: Int, size: CGSize) -> some View {
        if let url = item.thumb, let thumbSize = item.thumbSize {
            let sx = size.width / item.frame.width
            let knobSize = CGSize(width: thumbSize.width * sx, height: thumbSize.height * sx)
            let offset = knobs[index] ?? .zero
            let travel = min(size.width, size.height) * 0.28
            if let image = SkinArtwork.image(url, size: knobSize) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: knobSize.width, height: knobSize.height)
                    .offset(x: offset.x * travel, y: offset.y * travel)
            }
        }
    }
}

/// A button a recomposed skin has no picture of: a plain dark key.
private struct PlainSkinButton: View {
    let item: SkinItem
    let pressed: Bool

    var body: some View {
        switch item.inputs.first {
        case .swapScreens:
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(pressed ? 0.75 : 0.88))
                .overlay {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
        default:
            let wide = item.frame.width > item.frame.height * 1.4
            ZStack {
                if wide {
                    Capsule().fill(Color.black.opacity(pressed ? 0.6 : 0.45))
                } else {
                    Circle().fill(Color.black.opacity(pressed ? 0.6 : 0.45))
                }
                label
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        switch item.inputs.first {
        case .keyboard: Image(systemName: "keyboard.fill").font(.system(size: 14, weight: .semibold))
        case .menu: Image(systemName: "gearshape.fill").font(.system(size: 15, weight: .semibold))
        case .key(.start): Text("START").font(.system(size: 9, weight: .bold, design: .rounded))
        case .key(.select): Text("SELECT").font(.system(size: 9, weight: .bold, design: .rounded))
        case .key(.l2): Text("L2").font(.system(size: 14, weight: .bold, design: .rounded))
        case .key(.r2): Text("R2").font(.system(size: 14, weight: .bold, design: .rounded))
        case .key(.x): Text("X").font(.system(size: 18, weight: .bold, design: .rounded))
        case .key(.y): Text("Y").font(.system(size: 18, weight: .bold, design: .rounded))
        case .key(.l): Text("L").font(.system(size: 15, weight: .bold, design: .rounded))
        case .key(.r): Text("R").font(.system(size: 15, weight: .bold, design: .rounded))
        default: EmptyView()
        }
    }
}
