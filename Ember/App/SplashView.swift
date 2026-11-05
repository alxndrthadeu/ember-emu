import SwiftUI

/// The opening. It starts in the app icon's pixel art and settles into
/// the app's own look:
///
/// 1. One amber pixel blinks at the base, a coal (0.5 s).
/// 2. The fire lights up pixel by pixel into the icon's 9×10 flame, with
///    a few pixel sparks jumping up the grid (0.6 s, sprite pace).
/// 3. The pixels dissolve into the smooth gradient flame used inside
///    the app (a soft cross-blur).
/// 4. "Ember" rises in below, plain and light; a pause; a gentle fade
///    into the library.
///
/// About 3 s; a tap skips it. With Reduce Motion it is the still flame,
/// the name and a fade.
struct SplashView: View {
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Pixel phase, counted rather than timed: a busy launch delays
    /// frames but never skips them, so the coal always shows.
    @State private var frameIndex = 0
    @State private var smooth = false
    @State private var showName = false
    @State private var leaving = false
    @State private var finished = false

    private static let frame = 1.0 / 12
    private let flameHeight = PixelFlame.cell * 10

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()

            VStack(spacing: 26) {
                ZStack(alignment: .bottom) {
                    Canvas { canvas, size in
                        PixelFlame.draw(in: canvas, size: size,
                                        time: Double(frameIndex) * Self.frame, palette: palette)
                    }
                    .frame(width: PixelFlame.cell * 13, height: PixelFlame.cell * 15)
                    .opacity(smooth ? 0 : 1)
                    .blur(radius: smooth ? 8 : 0)
                    .scaleEffect(smooth ? 1.04 : 1, anchor: .bottom)

                    EmberFlame(size: flameHeight * 0.86)
                        .frame(height: flameHeight, alignment: .bottom)
                        .opacity(smooth ? 1 : 0)
                        .blur(radius: smooth ? 0 : 8)
                        .scaleEffect(smooth ? 1 : 0.94, anchor: .bottom)
                }

                Text(verbatim: "Ember")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Theme.primaryText)
                    .opacity(showName ? 1 : 0)
                    .offset(y: showName ? 0 : 10)
            }
            .offset(y: -20)
        }
        .opacity(leaving ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "Ember"))
        .task { await play() }
    }

    private var palette: PixelFlame.Palette {
        colorScheme == .dark ? .dark : .light
    }

    private func play() async {
        if reduceMotion {
            smooth = true
            showName = true
            try? await Task.sleep(for: .seconds(1.0))
            finish()
            return
        }
        // Coal and growth, frame by frame, then a beat on the whole
        // pixel flame.
        let pixelFrames = Int((PixelFlame.growEnd + 0.3) / Self.frame)
        for index in 0..<pixelFrames {
            guard !finished else { return }
            frameIndex = index
            try? await Task.sleep(for: .seconds(Self.frame))
        }
        withAnimation(.easeInOut(duration: 0.75)) { smooth = true }
        try? await Task.sleep(for: .seconds(0.45))
        withAnimation(.easeOut(duration: 0.7)) { showName = true }
        try? await Task.sleep(for: .seconds(1.1))
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeInOut(duration: 0.5)) { leaving = true }
        Task {
            try? await Task.sleep(for: .seconds(0.5))
            onFinish()
        }
    }
}

// MARK: - The pixel flame

/// The app icon's flame (scripts/make-app-icon.py): 1 edge, 2 middle,
/// 3 core, top to bottom.
private enum PixelFlame {
    static let cell: CGFloat = 12

    static let map = [
        "....1....",
        "...111...",
        "...1211..",
        "..12211..",
        "..122211.",
        ".1223221.",
        ".1233321.",
        ".1233321.",
        "..12321..",
        "...111...",
    ]

    struct Palette {
        let edge, middle, core: Color
        static let light = Palette(edge: Color(hex: 0xC83A1E), middle: Color(hex: 0xEE6A2A), core: Color(hex: 0xF7B538))
        static let dark = Palette(edge: Color(hex: 0xEE6A2A), middle: Color(hex: 0xF48A3A), core: Color(hex: 0xF7B538))

        func color(_ value: Int) -> Color {
            switch value {
            case 1: edge
            case 2: middle
            default: core
            }
        }
    }

    struct Pixel { let row, col, value: Int }

    /// Every lit pixel, in the order the fire reaches it: outward and
    /// upward from the coal at the base.
    static let pixels: [Pixel] = {
        var list: [Pixel] = []
        for (row, line) in map.enumerated() {
            for (col, ch) in line.enumerated() where ch != "." {
                list.append(Pixel(row: row, col: col, value: Int(String(ch))!))
            }
        }
        func reach(_ p: Pixel) -> Double {
            let dy = 8.0 - Double(p.row), dx = abs(Double(p.col) - 4)
            return max(dy, 0) + dx * 1.3 + (p.row > 8 ? 1 : 0)
        }
        return list.sorted { reach($0) < reach($1) }
    }()

    static let coalEnd = 0.5
    static let growEnd = 1.1

    static func draw(in canvas: GraphicsContext, size: CGSize, time t: Double, palette: Palette) {
        let origin = CGPoint(x: (size.width - cell * 9) / 2, y: size.height - cell * 10)
        func fill(_ rect: CGRect, _ color: Color) {
            canvas.fill(Path(rect), with: .color(color))
        }
        func cellRect(_ row: Int, _ col: Int) -> CGRect {
            CGRect(x: origin.x + CGFloat(col) * cell, y: origin.y + CGFloat(row) * cell, width: cell, height: cell)
        }
        let frame = Int(t * 12)

        if t < coalEnd {
            fill(cellRect(8, 4), frame % 4 < 2 ? palette.core : palette.middle)
            return
        }

        let growth = min(1, (t - coalEnd) / (growEnd - coalEnd))
        let shown = max(1, Int((Double(pixels.count) * growth).rounded(.up)))
        for pixel in pixels.prefix(shown) {
            fill(cellRect(pixel.row, pixel.col), palette.color(pixel.value))
        }

        for spark in sparks where t >= spark.start {
            let step = Int((t - spark.start) / spark.stepTime)
            guard step < spark.steps else { continue }
            let col = spark.col + (step >= spark.steps / 2 ? spark.drift : 0)
            let base = cellRect(spark.row - step, col)
            fill(base.insetBy(dx: cell / 4, dy: cell / 4), step >= spark.steps - 1 ? palette.middle : palette.core)
        }
    }

    struct Spark {
        let start: Double, row: Int, col: Int, drift: Int, steps: Int, stepTime: Double
    }

    static let sparks: [Spark] = [
        Spark(start: 0.25, row: 7, col: 4, drift: -1, steps: 5, stepTime: 0.08),
        Spark(start: 0.65, row: 4, col: 3, drift: -1, steps: 6, stepTime: 0.08),
        Spark(start: 0.85, row: 3, col: 6, drift: 1, steps: 6, stepTime: 0.07),
        Spark(start: 1.10, row: 0, col: 4, drift: 1, steps: 4, stepTime: 0.08),
    ]
}

#Preview {
    SplashView {}
}
