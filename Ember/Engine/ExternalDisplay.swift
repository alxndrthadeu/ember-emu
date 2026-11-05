import SwiftUI
import UIKit

/// AirPlay (or a cable) to a TV: the game moves to the TV, full screen,
/// and the iPhone becomes the controller. With no game open, the TV
/// shows a calm Ember screen.
///
/// iOS hands Ember a scene for the external display (the non-interactive
/// role in Info.plist). The engine's view moves into that scene's window,
/// and the engine is told the new size the same way a rotation tells it.
@MainActor
final class ExternalDisplay: ObservableObject {
    static let shared = ExternalDisplay()

    /// A TV (or other external display) is attached.
    @Published private(set) var isConnected = false

    private var window: UIWindow?
    let host = TVHostController()

    private init() {}

    func connect(_ scene: UIWindowScene) {
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        isConnected = true
        let detail = "\(Int(scene.screen.bounds.width))×\(Int(scene.screen.bounds.height)) pt, escala \(scene.screen.scale)"
        GameLog.shared.note("TV conectada: \(detail)")
        EmberTrail("TV conectada: \(detail)")
        print("[ember-tv] connected", scene.screen.bounds, scene.screen.scale)
    }

    func disconnect() {
        print("[ember-tv] disconnected")
        GameLog.shared.note("TV desconectada")
        EmberTrail("TV desconectada")
        window?.isHidden = true
        window = nil
        isConnected = false
    }

    /// Points and pixel scale of the TV, for the engine.
    var scale: CGFloat { window?.screen.scale ?? 1 }
}

/// The external display's scene (Info.plist:
/// UIWindowSceneSessionRoleExternalDisplayNonInteractive).
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        MainActor.assumeIsolated { ExternalDisplay.shared.connect(windowScene) }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        MainActor.assumeIsolated { ExternalDisplay.shared.disconnect() }
    }
}

/// The TV's root: the idle screen, or the game's view when one plays.
final class TVHostController: UIViewController {
    private let idle = UIHostingController(rootView: TVIdleView())
    private(set) weak var gameView: UIView?

    override func loadView() {
        view = UIView()
        view.backgroundColor = .black
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(idle)
        idle.view.frame = view.bounds
        idle.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        idle.view.backgroundColor = .clear
        view.addSubview(idle.view)
        idle.didMove(toParent: self)
    }

    /// Shows the game on the TV.
    func host(_ gameView: UIView) {
        loadViewIfNeeded()
        gameView.removeFromSuperview()
        gameView.frame = view.bounds
        gameView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(gameView, belowSubview: idle.view)
        idle.view.isHidden = true
        self.gameView = gameView
    }

    /// The game went back to the iPhone (or ended).
    func release() {
        gameView = nil
        idle.view.isHidden = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let gameView, gameView.superview == view {
            gameView.frame = view.bounds
            EngineSession.shared.externalViewDidResize(view.bounds.size)
        }
    }
}

/// The TV with no game: the night campfire of the app's identity.
private struct TVIdleView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x1E1814), Color(hex: 0x2A221D)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            RadialGradient(colors: [Theme.highlight.opacity(0.22), .clear], center: .center,
                           startRadius: 0, endRadius: 420)
            VStack(spacing: 22) {
                EmberFlame(size: 96)
                Text(verbatim: "Ember")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0xF4E9D8))
                Text("Escolha um jogo no iPhone")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(hex: 0xB9A794))
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

/// On the iPhone, where the picture was: the game is on the TV.
struct PlayingOnTVLabel: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tv")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.highlight)
            Text("Jogando na TV")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(hex: 0xF4E9D8))
            Text("O iPhone virou o controle")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: 0xB9A794))
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

extension EngineSession {
    /// The engine's view changed size outside a rotation (moved to or
    /// from a TV): the engine resizes as it would for a rotation.
    func externalViewDidResize(_ size: CGSize) {
        guard state == .running, size.width > 0, size.height > 0 else { return }
        EmberNotifyViewResized(Int32(size.width.rounded()), Int32(size.height.rounded()))
    }
}
