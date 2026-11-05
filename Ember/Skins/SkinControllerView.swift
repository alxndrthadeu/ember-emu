import GameController
import SwiftUI
import UIKit

/// What the player is pressing on the skin, for the artwork to show.
@MainActor
final class SkinTouchState: ObservableObject {
    @Published var pressed: Set<Int> = []
    @Published var held: [Int: GameKey] = [:]
}

/// A skin on screen: its artwork, cut open where the game picture is,
/// and a touch layer that turns fingers into game input.
struct SkinControllerView: View {
    let skin: Skin
    let layout: SkinLayout
    /// The game picture, in this view's coordinates: the artwork leaves
    /// a hole there, because the game draws below the controls.
    let pictureRect: CGRect
    let opacity: Double
    /// Old games: a keyboard button next to the menu button.
    var showKeyboard = false
    let onMenu: () -> Void
    var onKeyboard: () -> Void = {}

    @StateObject private var touches = SkinTouchState()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                artwork(size: geo.size)
                    .opacity(opacity)
                    .mask {
                        HoleShape(hole: pictureRect)
                            .fill(style: FillStyle(eoFill: true))
                    }
                // Built-in controls stay visible when they sit over the
                // picture (landscape on a near-square screen like an open
                // iPhone Duo). On phones they never overlap it.
                if case .builtIn(let style) = skin.source {
                    BuiltInSkinArt(style: style, layout: layout, pressed: touches.pressed,
                                   held: touches.held, layer: .controls)
                        .opacity(opacity)
                        .allowsHitTesting(false)
                }
                SkinTouchLayer(layout: layout, state: touches, onMenu: onMenu, onKeyboard: onKeyboard)

                // An imported skin has no keyboard button: put one next
                // to its menu button.
                if showKeyboard, !layout.hasKeyboardButton, let menu = layout.menuFrame {
                    let sx = geo.size.width / layout.mappingSize.width
                    let sy = geo.size.height / layout.mappingSize.height
                    let rect = menu.applying(.init(scaleX: sx, y: sy))
                    let size: CGFloat = 38
                    let x = rect.minX - size / 2 - 10 < size ? rect.maxX + size / 2 + 10 : rect.minX - size / 2 - 10
                    KeyboardButton(action: onKeyboard)
                        .position(x: x, y: rect.midY)
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func artwork(size: CGSize) -> some View {
        switch skin.source {
        case .builtIn(let style):
            BuiltInSkinArt(style: style, layout: layout, pressed: touches.pressed, held: touches.held,
                           layer: .shell)
        case .imported:
            ZStack(alignment: .topLeading) {
                if let url = layout.artwork, let image = SkinArtwork.image(url, size: size) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                }
                // Imported art is flat: show presses with a soft glow.
                let sx = size.width / layout.mappingSize.width
                let sy = size.height / layout.mappingSize.height
                ForEach(Array(touches.pressed), id: \.self) { index in
                    if index < layout.items.count {
                        let rect = layout.items[index].frame.applying(.init(scaleX: sx, y: sy))
                        Ellipse()
                            .fill(.white.opacity(0.28))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
        }
    }
}

/// The whole rect, minus a hole (filled even-odd).
struct HoleShape: Shape {
    let hole: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if !hole.isEmpty { path.addRect(hole) }
        return path
    }
}

// MARK: - Touch

private struct SkinTouchLayer: UIViewRepresentable {
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
    }

    private var hitsByTouch: [ObjectIdentifier: Hit] = [:]
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
        hit(at: point, previous: nil) != nil
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
        publish()
    }

    private func update(_ touch: UITouch) {
        let key = ObjectIdentifier(touch)
        let previous = hitsByTouch[key]
        let next = hit(at: touch.location(in: self), previous: previous)
        guard next != previous else { return }
        if let previous { release(previous) }
        if let next { press(next) }
        hitsByTouch[key] = next
        publish()
    }

    private func end(_ touch: UITouch) {
        let key = ObjectIdentifier(touch)
        if let hit = hitsByTouch.removeValue(forKey: key) { release(hit) }
        publish()
    }

    // MARK: Hit testing

    /// The item under a point: the one whose center is nearest, among
    /// those whose frame, grown by its extended edges, holds the point.
    private func hit(at point: CGPoint, previous: Hit?) -> Hit? {
        guard let layout, bounds.width > 0, bounds.height > 0 else { return nil }
        let sx = bounds.width / layout.mappingSize.width
        let sy = bounds.height / layout.mappingSize.height
        let p = CGPoint(x: point.x / sx, y: point.y / sy)

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
        case .dpad:
            return dpadHit(item, index: best.index, at: p, previous: previous)
        }
    }

    /// Four directions, with a dead zone in the middle and hysteresis on
    /// the diagonals, so a thumb resting at 45° does not flicker.
    private func dpadHit(_ item: SkinItem, index: Int, at p: CGPoint, previous: Hit?) -> Hit? {
        guard item.inputs.count == 4 else { return nil }
        let dx = p.x - item.frame.midX
        let dy = p.y - item.frame.midY
        guard hypot(dx, dy) >= min(item.frame.width, item.frame.height) * 0.1 else { return nil }

        let angle = atan2(dy, dx)
        let axes: [CGFloat] = [-.pi / 2, .pi / 2, .pi, 0]  // up, down, left, right
        if let previous, previous.index == index,
           let current = item.inputs.firstIndex(of: previous.input),
           angularDistance(angle, axes[current]) < .pi / 4 + .pi / 12 {
            return previous
        }
        let nearest = axes.indices.min { angularDistance(angle, axes[$0]) < angularDistance(angle, axes[$1]) }!
        return Hit(index: index, input: item.inputs[nearest])
    }

    // MARK: Input

    private func press(_ hit: Hit) {
        let count = counts[hit.input, default: 0]
        counts[hit.input] = count + 1
        guard count == 0 else { return }
        if AppSettings.haptics { Haptics.tap() }
        switch hit.input {
        case .key(let key):
            // Buttons follow the game's control profile; directions walk.
            if let button = ControlButton(skinKey: key) {
                ControlMapper.shared.press(button)
            } else {
                key.press()
            }
        case .menu: onMenu?()
        case .keyboard: onKeyboard?()
        case .fastForward: mkxp_setFastForwardMultiplier(Int32(AppSettings.fastForwardSpeed))
        case .toggleFastForward:
            let on = mkxp_getFastForwardMultiplier() > 1
            mkxp_setFastForwardMultiplier(on ? 1 : Int32(AppSettings.fastForwardSpeed))
        case .unsupported: break
        }
    }

    private func release(_ hit: Hit) {
        let count = counts[hit.input, default: 0]
        guard count > 0 else { return }
        counts[hit.input] = count - 1
        guard count == 1 else { return }
        switch hit.input {
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
        var held: [Int: GameKey] = [:]
        for hit in hitsByTouch.values {
            pressed.insert(hit.index)
            if layout.items[hit.index].kind == .dpad, case .key(let key) = hit.input {
                held[hit.index] = key
            }
        }
        MainActor.assumeIsolated {
            state.pressed = pressed
            state.held = held
        }
    }
}

private func angularDistance(_ a: CGFloat, _ b: CGFloat) -> CGFloat {
    let d = abs(a - b).truncatingRemainder(dividingBy: 2 * .pi)
    return d > .pi ? 2 * .pi - d : d
}

// MARK: - Physical controllers

/// The game controllers and keyboards connected, by Bluetooth or USB.
@MainActor
final class ControllerMonitor: ObservableObject {
    static let shared = ControllerMonitor()

    struct Device: Identifiable, Hashable {
        let id: String
        let name: String
        let symbol: String
        let battery: String?
    }

    @Published private(set) var connected = !GCController.controllers().isEmpty
    @Published private(set) var devices: [Device] = []
    /// The name of the controller that just connected, for a notice.
    @Published var justConnected: String?

    private init() {
        refresh()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.GCControllerDidConnect, .GCControllerDidDisconnect,
                                          .GCKeyboardDidConnect, .GCKeyboardDidDisconnect]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated {
                    let monitor = ControllerMonitor.shared
                    monitor.refresh()
                    if note.name == .GCControllerDidConnect, let controller = note.object as? GCController {
                        monitor.justConnected = controller.vendorName ?? "Controle"
                    }
                }
            }
        }
    }

    func refresh() {
        let pads = GCController.controllers().filter { $0.extendedGamepad != nil || $0.microGamepad != nil }
        connected = !pads.isEmpty
        var list = pads.enumerated().map { index, controller in
            Device(id: "pad\(index)\(controller.vendorName ?? "")",
                   name: controller.vendorName ?? "Controle",
                   symbol: Self.symbol(for: controller),
                   battery: Self.battery(controller.battery))
        }
        if GCKeyboard.coalesced != nil {
            list.append(Device(id: "keyboard", name: String(localized: "Teclado"), symbol: "keyboard", battery: nil))
        }
        devices = list
    }

    private static func symbol(for controller: GCController) -> String {
        let category = controller.productCategory.lowercased()
        if category.contains("dualsense") || category.contains("dualshock") || category.contains("playstation") {
            return "logo.playstation"
        }
        if category.contains("xbox") { return "logo.xbox" }
        return "gamecontroller.fill"
    }

    private static func battery(_ battery: GCDeviceBattery?) -> String? {
        guard let battery, battery.batteryState != .unknown else { return nil }
        let level = "\(Int(battery.batteryLevel * 100))%"
        return battery.batteryState == .charging ? "\(level) · carregando" : level
    }
}

/// The keyboard button outside a skin's own art.
struct KeyboardButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.controlLabel)
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .emberGlass(Theme.controlGlass.interactive(), in: Circle())
        .accessibilityLabel("Teclado")
    }
}
