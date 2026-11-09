import SwiftUI
import UIKit

/// What the player is pressing on the skin, for the artwork to show.
@MainActor
final class SkinTouchState: ObservableObject {
    @Published var pressed: Set<Int> = []
    @Published var held: [Int: Set<GameKey>] = [:]
    /// Where each analog stick's knob is, from -1 to 1 on each axis.
    @Published var knobs: [Int: CGPoint] = [:]
}

// MARK: - Touch

struct SkinTouchLayer: UIViewRepresentable {
    let layout: SkinLayout
    let state: SkinTouchState
    let onMenu: () -> Void
    let onKeyboard: () -> Void

    func makeUIView(context: Context) -> SkinTouchView {
        let view = SkinTouchView()
        view.state = state
        view.layout = layout
        view.onMenu = onMenu
        view.onKeyboard = onKeyboard
        return view
    }

    func updateUIView(_ view: SkinTouchView, context: Context) {
        if view.layout != layout {
            view.releaseAll()
            view.layout = layout
        }
        view.onMenu = onMenu
        view.onKeyboard = onKeyboard
    }

    static func dismantleUIView(_ view: SkinTouchView, coordinator: ()) {
        view.releaseAll()
    }
}

/// Maps every finger to the skin item under it. A finger can slide from
/// one button to another; two fingers on one button press it once.
final class SkinTouchView: UIView {
    var layout: SkinLayout?
    weak var state: SkinTouchState?
    var onMenu: (() -> Void)?
    var onKeyboard: (() -> Void)?

    private struct Hit: Hashable {
        let index: Int
        let input: SkinInput
        /// The second arrow of a diagonal.
        var extra: SkinInput?
    }

    private var hitsByTouch: [ObjectIdentifier: Hit] = [:]
    /// Knob position of a stick under a finger, by touch.
    private var knobsByTouch: [ObjectIdentifier: (index: Int, offset: CGPoint)] = [:]
    private var counts: [SkinInput: Int] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Touches that land on no item fall through (to nothing: the game
    /// takes no touch input).
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if hit(at: point, previous: nil) != nil { return true }
        // The dead zone in the middle of a D-pad or stick still takes the
        // touch, so sliding out of it steers.
        guard let layout else { return false }
        return layout.items.contains { item in
            (item.kind == .dpad || item.kind == .stick) && scaled(item.frame, layout).contains(point)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { update(touch) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { update(touch) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { end(touch) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { end(touch) }
    }

    func releaseAll() {
        for hit in hitsByTouch.values { release(hit) }
        hitsByTouch = [:]
        knobsByTouch = [:]
        publish()
    }

    private func update(_ touch: UITouch) {
        let key = ObjectIdentifier(touch)
        let previous = hitsByTouch[key]
        let point = touch.location(in: self)
        let next = hit(at: point, previous: previous)
        let knobBefore = knobsByTouch[key]?.offset
        updateKnob(for: key, at: point, hit: next)
        guard next != previous else {
            if knobsByTouch[key]?.offset != knobBefore { publish() }
            return
        }
        if let previous { release(previous) }
        if let next { press(next) }
        hitsByTouch[key] = next
        publish()
    }

    private func end(_ touch: UITouch) {
        let key = ObjectIdentifier(touch)
        if let hit = hitsByTouch.removeValue(forKey: key) { release(hit) }
        knobsByTouch.removeValue(forKey: key)
        publish()
    }

    /// The knob follows the thumb, up to the stick's rim.
    private func updateKnob(for key: ObjectIdentifier, at point: CGPoint, hit: Hit?) {
        guard let layout, let hit, layout.items.indices.contains(hit.index),
              layout.items[hit.index].kind == .stick else {
            knobsByTouch.removeValue(forKey: key)
            return
        }
        let index = hit.index
        let frame = scaled(layout.items[index].frame, layout)
        let radius = min(frame.width, frame.height) / 2
        var dx = (point.x - frame.midX) / radius
        var dy = (point.y - frame.midY) / radius
        let length = hypot(dx, dy)
        if length > 1 { dx /= length; dy /= length }
        knobsByTouch[key] = (index, CGPoint(x: dx, y: dy))
    }

    private func scaled(_ rect: CGRect, _ layout: SkinLayout) -> CGRect {
        let sx = bounds.width / layout.mappingSize.width
        let sy = bounds.height / layout.mappingSize.height
        return rect.applying(.init(scaleX: sx, y: sy))
    }

    // MARK: Hit testing

    /// The item under a point: the one whose center is nearest, among
    /// those whose frame, grown by its extended edges, holds the point.
    private func hit(at point: CGPoint, previous: Hit?) -> Hit? {
        guard let layout, bounds.width > 0, bounds.height > 0 else { return nil }
        let sx = bounds.width / layout.mappingSize.width
        let sy = bounds.height / layout.mappingSize.height
        let p = CGPoint(x: point.x / sx, y: point.y / sy)

        // A thumb on the D-pad or stick keeps steering it while it slides
        // a little past the edge.
        if let previous, layout.items.indices.contains(previous.index) {
            let item = layout.items[previous.index]
            if item.kind == .dpad || item.kind == .stick,
               hypot(p.x - item.frame.midX, p.y - item.frame.midY) < max(item.frame.width, item.frame.height) * 0.9 {
                return directionHit(item, index: previous.index, at: p, previous: previous)
            }
        }

        var best: (index: Int, distance: CGFloat)?
        for (index, item) in layout.items.enumerated() {
            let edges = item.extendedEdges ?? layout.extendedEdges
            let area = item.frame.inset(by: UIEdgeInsets(top: -edges.top, left: -edges.left,
                                                         bottom: -edges.bottom, right: -edges.right))
            guard area.contains(p) else { continue }
            let distance = hypot(p.x - item.frame.midX, p.y - item.frame.midY)
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        guard let best else { return nil }
        let item = layout.items[best.index]

        switch item.kind {
        case .button:
            guard let input = item.inputs.first else { return nil }
            return Hit(index: best.index, input: input)
        case .dpad, .stick:
            return directionHit(item, index: best.index, at: p, previous: previous)
        }
    }

    /// Eight directions: a diagonal holds two arrows, for games that walk
    /// diagonally (Input.dir8); the others read four. On the D-pad the
    /// diagonals are narrow (30°) so four-way games feel as before; on a
    /// stick all eight are even. A dead zone in the middle, and some
    /// hysteresis so a thumb on a boundary does not flicker.
    private func directionHit(_ item: SkinItem, index: Int, at p: CGPoint, previous: Hit?) -> Hit? {
        guard item.inputs.count == 4 else { return nil }
        let dx = p.x - item.frame.midX
        let dy = p.y - item.frame.midY
        let deadZone = item.kind == .stick ? 0.22 : 0.1
        guard hypot(dx, dy) >= min(item.frame.width, item.frame.height) * deadZone else { return nil }

        // Screen angle: 0 right, π/2 down.
        let angle = atan2(dy, dx)
        let diagonalHalf: CGFloat = item.kind == .stick ? .pi / 8 : .pi / 12
        let margin: CGFloat = .pi / 24
        func directions(_ angle: CGFloat, diagonalHalf: CGFloat) -> Set<Int> {
            // Indices into inputs: 0 up, 1 down, 2 left, 3 right.
            var result = Set<Int>()
            for (i, axis) in [(-CGFloat.pi / 2), .pi / 2, .pi, 0].enumerated()
            where angularDistance(angle, axis) < .pi / 2 - diagonalHalf {
                result.insert(i)
            }
            if result.isEmpty {
                // Inside a diagonal: the two axes around it.
                for (i, axis) in [(-CGFloat.pi / 2), .pi / 2, .pi, 0].enumerated()
                where angularDistance(angle, axis) <= .pi / 2 {
                    result.insert(i)
                }
            }
            return result
        }
        var chosen = directions(angle, diagonalHalf: diagonalHalf)
        if let previous, previous.index == index {
            // Keep the previous choice until the thumb is clearly past it.
            let before = Set([previous.input, previous.extra].compactMap { $0 }.compactMap { item.inputs.firstIndex(of: $0) })
            let wider = directions(angle, diagonalHalf: diagonalHalf + margin)
            let narrower = directions(angle, diagonalHalf: max(diagonalHalf - margin, 0))
            if before == wider || before == narrower { chosen = before }
        }
        let sorted = chosen.sorted()
        guard let first = sorted.first else { return nil }
        return Hit(index: index, input: item.inputs[first],
                   extra: sorted.count > 1 ? item.inputs[sorted[1]] : nil)
    }

    // MARK: Input

    private func press(_ hit: Hit) {
        press(hit.input)
        if let extra = hit.extra { press(extra) }
    }

    private func release(_ hit: Hit) {
        if let extra = hit.extra { release(extra) }
        release(hit.input)
    }

    private func press(_ input: SkinInput) {
        let count = counts[input, default: 0]
        counts[input] = count + 1
        guard count == 0 else { return }
        if AppSettings.haptics { Haptics.tap() }
        switch input {
        case .key(let key):
            // Buttons follow the game's control profile; directions walk.
            if let button = ControlButton(skinKey: key) {
                ControlMapper.shared.press(button)
            } else {
                key.press()
            }
        case .menu: onMenu?()
        case .keyboard: onKeyboard?()
        case .swapScreens:
            MainActor.assumeIsolated {
                withAnimation(.snappy) { SkinStore.shared.duoGameBelow.toggle() }
            }
        case .fastForward: mkxp_setFastForwardMultiplier(Int32(AppSettings.fastForwardSpeed))
        case .toggleFastForward:
            let on = mkxp_getFastForwardMultiplier() > 1
            mkxp_setFastForwardMultiplier(on ? 1 : Int32(AppSettings.fastForwardSpeed))
        case .unsupported: break
        }
    }

    private func release(_ input: SkinInput) {
        let count = counts[input, default: 0]
        guard count > 0 else { return }
        counts[input] = count - 1
        guard count == 1 else { return }
        switch input {
        case .key(let key):
            if let button = ControlButton(skinKey: key) {
                ControlMapper.shared.release(button)
            } else {
                key.release()
            }
        case .fastForward: GameSettings.apply()
        default: break
        }
    }

    private func publish() {
        guard let state, let layout else { return }
        var pressed = Set<Int>()
        var held: [Int: Set<GameKey>] = [:]
        for hit in hitsByTouch.values {
            pressed.insert(hit.index)
            let kind = layout.items[hit.index].kind
            guard kind == .dpad || kind == .stick else { continue }
            for input in [hit.input, hit.extra].compactMap({ $0 }) {
                if case .key(let key) = input { held[hit.index, default: []].insert(key) }
            }
        }
        var knobs: [Int: CGPoint] = [:]
        for knob in knobsByTouch.values { knobs[knob.index] = knob.offset }
        MainActor.assumeIsolated {
            state.pressed = pressed
            state.held = held
            state.knobs = knobs
        }
    }
}

private func angularDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    let d = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi)
    return d > .pi ? 2 * .pi - d : d
}
