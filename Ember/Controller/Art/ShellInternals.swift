import SwiftUI

/// What shows through a translucent shell: a circuit board with traces,
/// chips, capacitors and screws, drawn faintly in the shell's own deep
/// color. Laid out from a fixed seed, so it never changes between
/// frames, and in the layout's point space, so it scales with the skin.
struct ShellInternals: View {
    let palette: ShellPalette
    let mapping: CGSize
    /// The game picture: the board stays clear of it.
    let screen: CGRect?

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / mapping.width, y: size.height / mapping.height)
            draw(in: &context)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var board: CGRect {
        let inset: CGFloat = 14
        var rect = CGRect(origin: .zero, size: mapping).insetBy(dx: inset, dy: inset)
        let portrait = mapping.height > mapping.width
        if portrait, let screen {
            // Under the screen, where the controls are.
            rect = CGRect(x: inset, y: screen.maxY + 26, width: mapping.width - inset * 2,
                          height: mapping.height - screen.maxY - 26 - inset)
        }
        return rect
    }

    private func draw(in context: inout GraphicsContext) {
        var random = SeededRandom(seed: 0xE3B3)
        let board = self.board
        guard board.width > 40, board.height > 40 else { return }
        let ink = palette.deep
        let portrait = mapping.height > mapping.width

        // The board itself.
        let boardPath = Path(roundedRect: board, cornerRadius: 18)
        context.fill(boardPath, with: .color(ink.opacity(0.22)))
        context.stroke(boardPath, with: .color(ink.opacity(0.4)), lineWidth: 1.2)

        func point() -> CGPoint {
            CGPoint(x: board.minX + 12 + random.next() * (board.width - 24),
                    y: board.minY + 12 + random.next() * (board.height - 24))
        }
        func clamp(_ p: CGPoint) -> CGPoint {
            CGPoint(x: min(max(p.x, board.minX + 8), board.maxX - 8),
                    y: min(max(p.y, board.minY + 8), board.maxY - 8))
        }
        func avoidsScreen(_ p: CGPoint) -> Bool {
            guard let screen, !portrait else { return true }
            return !screen.insetBy(dx: -10, dy: -10).contains(p)
        }

        // Traces: runs of straight segments with right-angle and 45° bends.
        let traceCount = Int(board.width * board.height / 2600)
        for _ in 0..<min(traceCount, 70) {
            var p = point()
            guard avoidsScreen(p) else { continue }
            var path = Path()
            path.move(to: p)
            let bends = 2 + Int(random.next() * 3)
            var horizontal = random.next() < 0.5
            for _ in 0..<bends {
                let length = 18 + random.next() * 70
                let sign: CGFloat = random.next() < 0.5 ? -1 : 1
                if random.next() < 0.25 {
                    p = clamp(CGPoint(x: p.x + sign * length * 0.7, y: p.y + length * 0.7))
                } else if horizontal {
                    p = clamp(CGPoint(x: p.x + sign * length, y: p.y))
                } else {
                    p = clamp(CGPoint(x: p.x, y: p.y + sign * length))
                }
                guard avoidsScreen(p) else { break }
                path.addLine(to: p)
                horizontal.toggle()
            }
            context.stroke(path, with: .color(ink.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            context.fill(Path(ellipseIn: CGRect(x: p.x - 2.6, y: p.y - 2.6, width: 5.2, height: 5.2)),
                         with: .color(ink.opacity(0.6)))
        }

        // Chips, with their pins.
        for size in [CGSize(width: 46, height: 46), CGSize(width: 64, height: 26), CGSize(width: 30, height: 30)] {
            let origin = point()
            let chip = CGRect(x: min(origin.x, board.maxX - size.width - 10),
                              y: min(origin.y, board.maxY - size.height - 10),
                              width: size.width, height: size.height)
            guard avoidsScreen(CGPoint(x: chip.midX, y: chip.midY)) else { continue }
            let pins = Int(size.width / 7)
            for i in 0..<pins {
                let x = chip.minX + 4 + CGFloat(i) * (chip.width - 8) / CGFloat(max(pins - 1, 1))
                var pin = Path()
                pin.move(to: CGPoint(x: x, y: chip.minY - 4))
                pin.addLine(to: CGPoint(x: x, y: chip.maxY + 4))
                context.stroke(pin, with: .color(ink.opacity(0.55)), lineWidth: 1.6)
            }
            let body = Path(roundedRect: chip, cornerRadius: 3)
            context.fill(body, with: .color(palette.button.opacity(0.38)))
            context.stroke(body, with: .color(ink.opacity(0.5)), lineWidth: 1)
            context.fill(Path(ellipseIn: CGRect(x: chip.minX + 4, y: chip.minY + 4, width: 4, height: 4)),
                         with: .color(.white.opacity(0.15)))
        }

        // Capacitors.
        for _ in 0..<6 {
            let c = point()
            guard avoidsScreen(c) else { continue }
            let r = 4 + random.next() * 4
            let can = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            context.fill(can, with: .color(palette.light.opacity(0.22)))
            context.stroke(can, with: .color(ink.opacity(0.55)), lineWidth: 1)
        }

        // Screws at the board's corners.
        for corner in [CGPoint(x: board.minX + 14, y: board.minY + 14), CGPoint(x: board.maxX - 14, y: board.minY + 14),
                       CGPoint(x: board.minX + 14, y: board.maxY - 14), CGPoint(x: board.maxX - 14, y: board.maxY - 14)] {
            guard avoidsScreen(corner) else { continue }
            let head = Path(ellipseIn: CGRect(x: corner.x - 6, y: corner.y - 6, width: 12, height: 12))
            context.fill(head, with: .color(ink.opacity(0.55)))
            context.stroke(head, with: .color(.white.opacity(0.22)), lineWidth: 1)
            var cross = Path()
            cross.move(to: CGPoint(x: corner.x - 3.5, y: corner.y))
            cross.addLine(to: CGPoint(x: corner.x + 3.5, y: corner.y))
            cross.move(to: CGPoint(x: corner.x, y: corner.y - 3.5))
            cross.addLine(to: CGPoint(x: corner.x, y: corner.y + 3.5))
            context.stroke(cross, with: .color(.black.opacity(0.35)), lineWidth: 1.2)
        }
    }
}

/// A tiny deterministic generator (the same board every time).
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// A value from 0 to 1.
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
    }
}
