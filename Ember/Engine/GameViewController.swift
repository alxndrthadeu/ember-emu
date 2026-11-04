import Combine
import SwiftUI
import UIKit

/// Where the game picture sits, as the engine reports it.
@MainActor
final class GameLayout: ObservableObject {
    static let shared = GameLayout()

    /// The picture's frame in the game screen, in points.
    @Published private(set) var pictureRect: CGRect = .zero
    /// Width / height of the game's own resolution (608x416 -> 1.46).
    @Published private(set) var aspect: CGFloat?

    private init() {}

    /// Starts listening. The engine fires the callback on its own
    /// thread whenever the picture moves or resizes.
    func observeEngine() {
        pictureRect = .zero
        aspect = nil
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
    private var aspectObservation: AnyCancellable?
    private weak var gameView: UIView?
    private let textField = GameTextField()

    /// The game asked for text (or stopped asking): show or hide the
    /// keyboard.
    func setTextInputActive(_ active: Bool) {
        textField.setActive(active)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        controls.view.backgroundColor = .clear
        controls.view.frame = view.bounds
        controls.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addChild(controls)
        view.addSubview(controls.view)
        controls.didMove(toParent: self)
        controls.view.isMultipleTouchEnabled = true

        textField.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        view.addSubview(textField)

        aspectObservation = GameLayout.shared.$aspect.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateViewport() }
        }
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

        guard size.height >= size.width else {
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
