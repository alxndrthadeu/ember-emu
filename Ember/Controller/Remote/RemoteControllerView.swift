import SwiftUI
import UIKit

/// Presents the controller full screen, locked in landscape.
@MainActor
enum RemoteControllerScreen {
    static func present() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var top = scene.keyWindow?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let controller = LandscapeHostingController(rootView: RemoteControllerView())
        controller.modalPresentationStyle = .fullScreen
        // Back to how the iPhone was held before (portrait, usually) when
        // the controller closes.
        controller.scene = scene
        controller.returnTo = scene.effectiveGeometry.interfaceOrientation.isLandscape ? nil : .portrait
        top.present(controller, animated: true) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        }
    }
}

private final class LandscapeHostingController: UIHostingController<RemoteControllerView> {
    weak var scene: UIWindowScene?
    /// The orientation to go back to on closing; nil leaves it as it is.
    var returnTo: UIInterfaceOrientationMask?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    /// Once gone, only the screen below decides the orientations, so
    /// asking for portrait now works.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard let scene, let returnTo else { return }
        var top = scene.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: returnTo))
    }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
}

/// The iPhone as a controller: no game picture, big buttons, always in
/// landscape. The gear opens the game's menu (speed, states, cheats,
/// quit) on the Mac; the keyboard types into the game.
struct RemoteControllerView: View {
    @Bindable private var client = RemoteControllerClient.shared
    @Environment(\.dismiss) private var dismiss
    @State private var typing = false
    @State private var confirmingQuit = false

    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.height / 3.6, geo.size.width / 8)
            ZStack {
                Theme.controllerBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    // L, the game and its state, R.
                    HStack(alignment: .top, spacing: 12) {
                        shoulder(.l, width: unit * 2.2)
                        if client.controllerType == .modern { shoulder(.l2, width: unit * 1.2) }
                        Spacer()
                        status
                        Spacer()
                        if client.controllerType == .modern { shoulder(.r2, width: unit * 1.2) }
                        shoulder(.r, width: unit * 2.2)
                    }
                    Spacer(minLength: 0)
                    HStack(alignment: .center) {
                        RemoteDPad(size: unit * 2.4)
                            .padding(.leading, unit * 0.3)
                        Spacer()
                        VStack(spacing: unit * 0.35) {
                            HStack(spacing: unit * 0.4) {
                                RemoteRoundButton(icon: "gearshape.fill", size: unit * 0.8) { gearMenu }
                                RemoteRoundButton(icon: "keyboard", size: unit * 0.8) { typing = true }
                            }
                            HStack(spacing: unit * 0.3) {
                                RemotePill(button: .select, width: unit * 1.2)
                                RemotePill(button: .start, width: unit * 1.2)
                            }
                        }
                        Spacer()
                        faceButtons(unit: unit)
                            .padding(.trailing, unit * 0.3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

                if typing {
                    RemoteKeyboardField(onDone: { typing = false })
                        .frame(width: 1, height: 1)
                        .opacity(0.01)
                }
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("Sair do jogo no Mac?", isPresented: $confirmingQuit, titleVisibility: .visible) {
            Button("Sair do jogo", role: .destructive) { client.command(.quit) }
        } message: {
            Text("O progresso que não foi salvo no jogo será perdido.")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            client.send(.releaseAll)
        }
    }

    // MARK: Pieces

    private var status: some View {
        VStack(spacing: 4) {
            switch client.state {
            case .connected(let name):
                Label {
                    Text(verbatim: client.gameTitle.isEmpty ? name : client.gameTitle).lineLimit(1)
                } icon: {
                    Image(systemName: "macbook")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.controlLabel)
                Group {
                    if let latency = client.latency {
                        Text("Jogando no Mac · \(latency.formatted(.units(allowed: [.milliseconds], width: .narrow)))\(client.direct ? " · direto" : "")")
                    } else {
                        Text("Jogando no Mac")
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.controlLabel.opacity(0.6))
                if let notice = client.notice {
                    Label(notice, systemImage: "checkmark.icloud.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.onHighlight)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.highlight))
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityAddTraits(.updatesFrequently)
                }
            case .connecting:
                ProgressView().tint(Theme.controlLabel)
                Text("Conectando…").font(.caption).foregroundStyle(Theme.controlLabel.opacity(0.7))
            case .lost:
                Button {
                    client.reconnect()
                } label: {
                    Label("Reconectar", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                Text("O Mac saiu do alcance ou o jogo fechou.").font(.caption).foregroundStyle(Theme.controlLabel.opacity(0.7))
            case .idle:
                EmptyView()
            }
            Button("Desconectar") {
                client.disconnect()
                dismiss()
            }
            .font(.caption)
            .foregroundStyle(Theme.controlLabel.opacity(0.6))
        }
        .frame(maxWidth: 260)
        .animation(.spring(response: 0.3), value: client.notice)
    }

    @ViewBuilder
    private var gearMenu: some View {
        Menu {
            Picker("Velocidade", selection: Binding(get: { client.speed },
                                                    set: { client.command(.speed, "\($0)") })) {
                ForEach(GameSettings.speedSteps, id: \.self) { Text("\($0)x").tag($0) }
            }
            Button("Salvar estado", systemImage: "square.and.arrow.down") { client.command(.saveState) }
            Button("Carregar o último estado", systemImage: "clock.arrow.circlepath") { client.command(.loadState) }
            Button("Cheats", systemImage: "wand.and.stars") { client.command(.cheats) }
            Divider()
            Button("Sair do jogo", systemImage: "xmark.circle", role: .destructive) { confirmingQuit = true }
        } label: {
            Image(systemName: "gearshape.fill")
        }
    }

    private func shoulder(_ button: ControlButton, width: CGFloat) -> some View {
        RemotePressable(button: button) { pressed in
            Text(button == .l2 ? "L2" : button == .r2 ? "R2" : button.label)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.controlLabel)
                .frame(width: width, height: 52)
                .background(Capsule().fill(RemoteColors.fill(pressed)))
        }
    }

    @ViewBuilder
    private func faceButtons(unit: CGFloat) -> some View {
        let size = unit * 1.05
        if client.controllerType == .classic2 {
            // GBA: B low-left, A high-right.
            ZStack {
                RemoteFace(button: .b, size: size).offset(x: -unit * 0.62, y: unit * 0.38)
                RemoteFace(button: .a, size: size).offset(x: unit * 0.62, y: -unit * 0.38)
            }
            .frame(width: unit * 2.5, height: unit * 2.2)
        } else {
            // Four in a diamond: Y left, X top, A right, B bottom.
            ZStack {
                RemoteFace(button: .x, size: size * 0.85).offset(y: -unit * 0.78)
                RemoteFace(button: .y, size: size * 0.85).offset(x: -unit * 0.78)
                RemoteFace(button: .a, size: size * 0.85).offset(x: unit * 0.78)
                RemoteFace(button: .b, size: size * 0.85).offset(y: unit * 0.78)
            }
            .frame(width: unit * 2.45, height: unit * 2.45)
        }
    }
}

/// The controller's buttons: dark on the dark background, lighter while
/// pressed (glass over an empty dark screen turns grey).
enum RemoteColors {
    static func fill(_ pressed: Bool) -> Color {
        pressed ? Color(hex: 0x4A3D34) : Color(hex: 0x2B211C)
    }
}

/// Sends a button down while touched and up when let go.
private struct RemotePressable<Label: View>: View {
    let button: ControlButton
    @ViewBuilder let label: (Bool) -> Label
    @State private var pressed = false

    var body: some View {
        label(pressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        RemoteControllerClient.shared.press(button)
                    }
                    .onEnded { _ in
                        pressed = false
                        RemoteControllerClient.shared.release(button)
                    }
            )
            .accessibilityLabel(Text(button.label))
            .accessibilityAddTraits(.isButton)
    }
}

private struct RemoteFace: View {
    let button: ControlButton
    let size: CGFloat

    var body: some View {
        RemotePressable(button: button) { pressed in
            Text(button.label)
                .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.controlLabel)
                .frame(width: size, height: size)
                .background(Circle().fill(RemoteColors.fill(pressed)))
        }
    }
}

private struct RemotePill: View {
    let button: ControlButton
    let width: CGFloat

    var body: some View {
        RemotePressable(button: button) { pressed in
            Text(button.label.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.controlLabel)
                .frame(width: width, height: 40)
                .background(Capsule().fill(RemoteColors.fill(pressed)))
        }
    }
}

private struct RemoteRoundButton<MenuContent: View>: View {
    let icon: String
    let size: CGFloat
    @ViewBuilder var content: () -> MenuContent

    init(icon: String, size: CGFloat, @ViewBuilder content: @escaping () -> MenuContent) {
        self.icon = icon
        self.size = size
        self.content = content
    }

    init(icon: String, size: CGFloat, action: @escaping () -> Void) where MenuContent == Button<Image> {
        self.icon = icon
        self.size = size
        self.content = { Button(action: action) { Image(systemName: icon) } }
    }

    var body: some View {
        content()
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(Theme.controlLabel)
            .frame(width: size, height: size)
            .background(Circle().fill(RemoteColors.fill(false)))
            .buttonStyle(.plain)
    }
}

/// A D-pad with eight directions: diagonals send two arrows (narrow, so
/// four-direction games don't slip).
private struct RemoteDPad: View {
    let size: CGFloat
    @State private var held: Set<ControlDirection> = []

    var body: some View {
        ZStack {
            Group {
                RoundedRectangle(cornerRadius: 14).frame(width: size * 0.36, height: size)
                RoundedRectangle(cornerRadius: 14).frame(width: size, height: size * 0.36)
            }
            .foregroundStyle(Color(hex: 0x2B211C))
            ForEach(ControlDirection.allCases) { direction in
                Image(systemName: direction.symbol)
                    .font(.system(size: size * 0.12, weight: .bold))
                    .foregroundStyle(Theme.controlLabel.opacity(held.contains(direction) ? 1 : 0.55))
                    .offset(offset(direction))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in update(to: directions(at: value.location)) }
                .onEnded { _ in update(to: []) }
        )
        .accessibilityLabel("Direcional")
    }

    private func offset(_ direction: ControlDirection) -> CGSize {
        let d = size * 0.34
        switch direction {
        case .up: return CGSize(width: 0, height: -d)
        case .down: return CGSize(width: 0, height: d)
        case .left: return CGSize(width: -d, height: 0)
        case .right: return CGSize(width: d, height: 0)
        }
    }

    private func directions(at point: CGPoint) -> Set<ControlDirection> {
        let dx = point.x - size / 2, dy = point.y - size / 2
        guard hypot(dx, dy) > size * 0.1 else { return [] }
        let angle = atan2(-dy, dx) * 180 / .pi   // 0 = right, 90 = up
        // 30° diagonals, 60° straight.
        switch angle {
        case -30..<30: return [.right]
        case 30..<60: return [.right, .up]
        case 60..<120: return [.up]
        case 120..<150: return [.up, .left]
        case -60 ..< -30: return [.right, .down]
        case -120 ..< -60: return [.down]
        case -150 ..< -120: return [.down, .left]
        default: return [.left]
        }
    }

    private func update(to new: Set<ControlDirection>) {
        guard new != held else { return }
        let client = RemoteControllerClient.shared
        for direction in held.subtracting(new) { client.release(direction) }
        for direction in new.subtracting(held) { client.press(direction) }
        if !new.subtracting(held).isEmpty { Haptics.tap() }
        held = new
    }
}

/// The iPhone's keyboard, typing into the game on the Mac: letters as
/// text, Return as Enter, delete as Backspace.
private struct RemoteKeyboardField: UIViewRepresentable {
    let onDone: () -> Void

    func makeUIView(context: Context) -> RemoteTextField {
        let field = RemoteTextField()
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.returnKeyType = .done
        field.onDone = onDone
        // OK above the keyboard: Return goes to the game as Enter, so the
        // keyboard needs its own way to close.
        let bar = UIToolbar()
        bar.sizeToFit()
        bar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: String(localized: "OK"), primaryAction: UIAction { [weak field] _ in
                field?.resignFirstResponder()
            }),
        ]
        field.inputAccessoryView = bar
        DispatchQueue.main.async { field.becomeFirstResponder() }
        return field
    }

    func updateUIView(_ uiView: RemoteTextField, context: Context) {}
}

final class RemoteTextField: UITextField, UITextFieldDelegate {
    var onDone: () -> Void = {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func insertText(_ text: String) {
        if text == "\n" {
            RemoteControllerClient.shared.send(.key, "enter")
        } else {
            RemoteControllerClient.shared.send(.text, text)
        }
    }

    override func deleteBackward() {
        RemoteControllerClient.shared.send(.key, "backspace")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        RemoteControllerClient.shared.send(.key, "enter")
        return false
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        onDone()
    }
}
