import Foundation
import GameController

/// Reads game controllers directly, so they follow the game's profile.
/// The engine's own controller reading is turned off while it runs
/// (mkxp_setGameControllerCaptureEnabled), or input would double.
@MainActor
final class PhysicalControllerInput {
    static let shared = PhysicalControllerInput()

    private var observers: [NSObjectProtocol] = []
    /// Directions held by each source (D-pad, left stick).
    private var held: [String: Set<GameKey>] = [:]
    private var pressedDirections: Set<GameKey> = []

    private init() {}

    func start() {
        mkxp_setGameControllerCaptureEnabled(false)
        GCController.controllers().forEach(bind)
        bindKeyboard()
        observers.append(NotificationCenter.default.addObserver(
            forName: .GCKeyboardDidConnect, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PhysicalControllerInput.shared.bindKeyboard() }
        })
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { note in
            guard let controller = note.object as? GCController else { return }
            MainActor.assumeIsolated { PhysicalControllerInput.shared.bind(controller) }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                ControlMapper.shared.releaseAll()
                PhysicalControllerInput.shared.releaseDirections()
            }
        })
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        for controller in GCController.controllers() {
            controller.extendedGamepad?.valueChangedHandler = nil
        }
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = nil
        releaseDirections()
        ControlMapper.shared.releaseAll()
    }

    /// A Bluetooth or USB keyboard reaches the game as a PC keyboard:
    /// GameController key codes are USB HID usages, the same numbers as
    /// the engine's (SDL) scancodes. While the player types a name, keys
    /// go to the text field only.
    func bindKeyboard() {
        guard let keyboard = GCKeyboard.coalesced, let input = keyboard.keyboardInput else { return }
        keyboard.handlerQueue = .main
        input.keyChangedHandler = { _, _, keyCode, pressed in
            MainActor.assumeIsolated {
                guard !EngineSession.shared.isTyping else { return }
                mkxp_injectKeyEvent(Int32(keyCode.rawValue), pressed ? 1 : 0)
            }
        }
    }

    private func bind(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        controller.handlerQueue = .main
        let buttons: [(GCControllerButtonInput?, ControlButton)] = [
            (pad.buttonA, .a), (pad.buttonB, .b), (pad.buttonX, .x), (pad.buttonY, .y),
            (pad.leftShoulder, .l), (pad.rightShoulder, .r),
            (pad.leftTrigger, .l2), (pad.rightTrigger, .r2),
            (pad.buttonMenu, .start), (pad.buttonOptions, .select),
        ]
        for (input, button) in buttons {
            input?.pressedChangedHandler = { _, _, pressed in
                MainActor.assumeIsolated {
                    pressed ? ControlMapper.shared.press(button) : ControlMapper.shared.release(button)
                }
            }
        }
        pad.dpad.valueChangedHandler = { _, x, y in
            MainActor.assumeIsolated { PhysicalControllerInput.shared.setDirections(x, y, source: "dpad") }
        }
        pad.leftThumbstick.valueChangedHandler = { _, x, y in
            MainActor.assumeIsolated { PhysicalControllerInput.shared.setDirections(x, y, source: "stick") }
        }
    }

    /// Four-way, like the on-screen D-pad: the stronger axis wins.
    private func setDirections(_ x: Float, _ y: Float, source: String) {
        var keys = Set<GameKey>()
        let threshold: Float = 0.5
        // Eight directions: a diagonal holds two arrows, and games that
        // walk diagonally (Input.dir8) do; the rest read four.
        if max(abs(x), abs(y)) >= threshold {
            let angle = atan2(Double(y), Double(x))
            let sector = Int((angle / (.pi / 4)).rounded()) & 7  // 0 right, 2 up, 4 left, 6 down
            if [7, 0, 1].contains(sector) { keys.insert(.right) }
            if [1, 2, 3].contains(sector) { keys.insert(.up) }
            if [3, 4, 5].contains(sector) { keys.insert(.left) }
            if [5, 6, 7].contains(sector) { keys.insert(.down) }
        }
        held[source] = keys
        apply()
    }

    private func apply() {
        let wanted = held.values.reduce(into: Set<GameKey>()) { $0.formUnion($1) }
        for key in pressedDirections.subtracting(wanted) { key.release() }
        for key in wanted.subtracting(pressedDirections) { key.press() }
        pressedDirections = wanted
    }

    private func releaseDirections() {
        held = [:]
        apply()
    }
}
