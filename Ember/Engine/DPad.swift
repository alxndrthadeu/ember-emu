import SwiftUI
import UIKit

/// A cross-shaped D-pad.
///
/// Touches are tracked in UIKit, not with a SwiftUI gesture: UIKit
/// reports the touch the moment the finger lands, and the direction
/// logic needs every move event.
struct DPad: View {
    var size: CGFloat = 156
    @State private var direction: GameKey?

    var body: some View {
        ZStack {
            Cross(armWidth: size * 0.36, radius: 10)
                .fill(Theme.controlFill)
                .overlay(Cross(armWidth: size * 0.36, radius: 10)
                    .stroke(Theme.controlStroke, lineWidth: 1))
                .frame(width: size, height: size)

            ForEach([GameKey.up, .down, .left, .right], id: \.self) { key in
                Image(systemName: "arrowtriangle.\(arrowName(key)).fill")
                    .font(.system(size: 15))
                    .foregroundStyle(direction == key ? Theme.accent : Theme.controlLabel)
                    .offset(arrowOffset(key))
            }
        }
        // The touch area reaches past the drawing: a thumb that drifts
        // off the cross keeps walking.
        .frame(width: size + 44, height: size + 44)
        .overlay(DirectionTracker(direction: $direction))
    }

    private func arrowName(_ key: GameKey) -> String {
        switch key {
        case .up: "up"
        case .down: "down"
        case .left: "left"
        default: "right"
        }
    }

    private func arrowOffset(_ key: GameKey) -> CGSize {
        let d = size * 0.34
        switch key {
        case .up: return CGSize(width: 0, height: -d)
        case .down: return CGSize(width: 0, height: d)
        case .left: return CGSize(width: -d, height: 0)
        default: return CGSize(width: d, height: 0)
        }
    }
}

/// A plus sign with rounded arm ends.
private struct Cross: Shape {
    let armWidth: CGFloat
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let h = CGRect(x: rect.minX, y: rect.midY - armWidth / 2,
                       width: rect.width, height: armWidth)
        let v = CGRect(x: rect.midX - armWidth / 2, y: rect.minY,
                       width: armWidth, height: rect.height)
        return Path(roundedRect: h, cornerRadius: radius)
            .union(Path(roundedRect: v, cornerRadius: radius))
    }
}

private struct DirectionTracker: UIViewRepresentable {
    @Binding var direction: GameKey?

    func makeUIView(context: Context) -> DirectionTouchView {
        let view = DirectionTouchView()
        view.onChange = { direction = $0 }
        return view
    }

    func updateUIView(_ view: DirectionTouchView, context: Context) {}

    static func dismantleUIView(_ view: DirectionTouchView, coordinator: ()) {
        view.releaseAll()
    }
}

/// Turns one finger's position into one of four directions.
final class DirectionTouchView: UIView {
    var onChange: ((GameKey?) -> Void)?

    private weak var trackedTouch: UITouch?
    private var current: GameKey?

    /// Below this distance from the center, no direction is held.
    private var deadZone: CGFloat { bounds.width * 0.09 }
    /// How far past the 45° diagonal the finger must go before the
    /// direction switches. Stops ↑/→ flicker on a diagonal thumb.
    private let hysteresis: CGFloat = .pi / 12

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackedTouch == nil, let touch = touches.first else { return }
        trackedTouch = touch
        update(with: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        update(with: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackedTouch, touches.contains(touch) else { return }
        releaseAll()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseAll()
    }

    func releaseAll() {
        trackedTouch = nil
        set(nil)
    }

    private func update(with point: CGPoint) {
        let dx = point.x - bounds.midX
        let dy = point.y - bounds.midY
        guard hypot(dx, dy) >= deadZone else {
            set(nil)
            return
        }

        let angle = atan2(dy, dx)  // y grows downward
        if let current, angularDistance(angle, Self.axis(of: current)) < .pi / 4 + hysteresis {
            return
        }
        set(Self.nearest(to: angle))
    }

    private func set(_ key: GameKey?) {
        guard key != current else { return }
        current?.release()
        key?.press()
        current = key
        if key != nil { Haptics.tap() }
        onChange?(key)
    }

    private static func axis(of key: GameKey) -> CGFloat {
        switch key {
        case .right: 0
        case .down: .pi / 2
        case .left: .pi
        default: -.pi / 2
        }
    }

    private static func nearest(to angle: CGFloat) -> GameKey {
        let keys: [GameKey] = [.right, .down, .left, .up]
        return keys.min { angularDistance(angle, axis(of: $0)) < angularDistance(angle, axis(of: $1)) }!
    }
}

private func angularDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    let d = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi)
    return d > .pi ? 2 * .pi - d : d
}
