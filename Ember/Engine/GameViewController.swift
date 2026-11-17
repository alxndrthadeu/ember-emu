import SwiftUI
import UIKit

/// Where the game picture sits, as the engine reports it.
@MainActor
@Observable
final class GameLayout {
    static let shared = GameLayout()

    /// The picture's frame in the game screen, in points.
    private(set) var pictureRect: CGRect = .zero
    /// Width / height of the game's own resolution (608x416 -> 1.46).
    private(set) var aspect: CGFloat?
    /// Height / width of the game screen itself (2.17 on most iPhones,
    /// about 1.46 on an open iPhone Duo). Built-in skins reshape for
    /// screens wider than a phone.
    private(set) var viewAspect: CGFloat?
    /// The game shows on a TV or computer browser (TVStream); the
    /// iPhone shows only the controller.
    var onTV = false
    /// An iPhone Duo half folded (tabletop or book posture): the split
    /// layouts keep a wider gap around the fold.
    var hingePartiallyOpen = false

    /// Called on every layout of the game screen; publishes only real
    /// changes (folding, unfolding, rotating), so layout cannot loop.
    func setViewSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let value = (max(size.width, size.height) / min(size.width, size.height) * 100).rounded() / 100
        if value != viewAspect { viewAspect = value }
    }

    private init() {}

    /// Starts listening. The engine fires the callback on its own
    /// thread whenever the picture moves or resizes.
    func observeEngine() {
        pictureRect = .zero
        aspect = nil
        Self.installRectCallback()
    }

    /// Nonisolated: the closure runs on the engine's thread, and in a
    /// main-actor method Swift 6 would check (and trap) that it doesn't.
    nonisolated private static func installRectCallback() {
        mkxp_setGameRectChangedCallback({ x, y, w, h, _ in
            let rect = CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(w), height: CGFloat(h))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { GameLayout.shared.update(rect) }
            }
        }, nil)
    }

    private func update(_ rect: CGRect) {
        pictureRect = rect
        guard rect.width > 0, rect.height > 0 else { return }
        let newAspect = rect.width / rect.height
        if aspect.map({ abs($0 - newAspect) > 0.01 }) ?? true {
            aspect = newAspect
        }
    }
}

/// The game screen: SDL's game view at the bottom, Ember's controls
/// on top, in Ember's own window.
///
/// One window only. Two stacked UIWindows (SDL's and the app's) break
/// compositing on a real device, so SDL's view moves in here and its
/// window stays hidden. That also puts the status bar and the home
/// indicator under Ember's control.
final class GameViewController: UIViewController {
    private let controls = UIHostingController(rootView: ControlsOverlay())
    private var screenObservation: ObservationLoop?
    private weak var gameView: UIView?
    private let textField = GameTextField()

    /// The game asked for text (or stopped asking): show or hide the
    /// keyboard.
    func setTextInputActive(_ active: Bool) {
        textField.setActive(active)
    }

    /// The menu's "Teclado": the system keyboard on demand, for games
    /// that never ask for text input (they poll a PC keyboard).
    func openKeyboard() {
        textField.openManually()
    }

    var isTyping: Bool { textField.isFirstResponder }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    /// iPhone Duo (iOS 27.1+): follows the hinge so the split layouts
    /// can widen the gap when the device is half folded.
    private func watchHinge() {
        #if DEBUG
        // Development aid: EMBER_HINGE=partial acts as a half-folded Duo
        // (the simulator does not fold).
        if ProcessInfo.processInfo.environment["EMBER_HINGE"] == "partial" {
            GameLayout.shared.hingePartiallyOpen = true
            return
        }
        #endif
        guard #available(iOS 27.1, *) else { return }
        let interaction = UIHingeInteraction { _, update in
            let partial = update.hinge?.status == .partiallyOpen
            if GameLayout.shared.hingePartiallyOpen != partial {
                GameLayout.shared.hingePartiallyOpen = partial
            }
        }
        view.addInteraction(interaction)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // The game screen is dark in both modes (CLAUDE.md), and so is
        // everything it presents: the menu sheet's glass, dialogs.
        overrideUserInterfaceStyle = .dark
        watchHinge()

        controls.view.backgroundColor = .clear
        controls.view.frame = view.bounds
        controls.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addChild(controls)
        view.addSubview(controls.view)
        controls.didMove(toParent: self)
        controls.view.isMultipleTouchEnabled = true

        textField.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        view.addSubview(textField)

        // The picture moves with the game's proportion and the screen modes.
        screenObservation = ObservationLoop(read: {
            _ = GameLayout.shared.aspect
            _ = GameLayout.shared.hingePartiallyOpen
            _ = SkinStore.shared.portraitFullWidth
            _ = SkinStore.shared.duoSplit
            _ = SkinStore.shared.duoGameBelow
        }) { [weak self] in self?.updateViewport() }
    }

    /// Moves SDL's view out of SDL's window and under the controls.
    func adopt(gameWindow window: UIWindow) -> Bool {
        guard let gameView = window.rootViewController?.view else { return false }
        gameView.removeFromSuperview()
        gameView.frame = view.bounds
        gameView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(gameView, at: 0)
        self.gameView = gameView

        window.isHidden = true
        self.view.window?.makeKeyAndVisible()
        updateViewport()
        #if DEBUG
        // Development aid: EMBER_ORIENTATION=landscape turns the screen,
        // so landscape can be checked in the simulator.
        if ProcessInfo.processInfo.environment["EMBER_ORIENTATION"] == "landscape",
           let scene = view.window?.windowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        }
        #endif
        return true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateViewport()
    }

    /// Portrait: the picture spans the full width under the safe area,
    /// and the controller takes the rest. Landscape: the engine fits
    /// the picture to the screen and the controls float over it.
    private func updateViewport() {
        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else { return }

        let portrait = size.height >= size.width
        GameLayout.shared.setViewSize(size)

        // The skin says where the game goes, in its own point space,
        // stretched to the screen like the artwork.
        let layout = SkinStore.shared.layout(portrait: portrait)
        if let screen = layout.screen {
            let mapping = layout.mappingSize
            mkxp_setHostViewportRegion(Float(screen.minX / mapping.width),
                                       Float(screen.minY / mapping.height),
                                       Float(screen.width / mapping.width),
                                       Float(screen.height / mapping.height),
                                       portrait)
            return
        }

        guard portrait else {
            mkxp_clearHostViewportRegion()
            return
        }

        // Until the engine reports the real picture, assume 4:3.
        let aspect = GameLayout.shared.aspect ?? (4.0 / 3.0)
        let top = view.safeAreaInsets.top
        let height = min(size.width / aspect, size.height - top)
        mkxp_setHostViewportRegion(0,
                                   Float(top / size.height),
                                   1,
                                   Float(height / size.height),
                                   true)
    }
}
