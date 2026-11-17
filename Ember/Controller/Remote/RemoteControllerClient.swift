import Foundation
import Network
import Observation
import UIKit

/// The iPhone's side of "Usar como controle": finds Macs playing a game
/// nearby (Bonjour, peer-to-peer on, so no shared Wi-Fi is needed),
/// connects to one and sends what the buttons do.
@MainActor
@Observable
final class RemoteControllerClient {
    static let shared = RemoteControllerClient()

    struct Host: Identifiable, Hashable {
        let name: String
        let endpoint: NWEndpoint
        var id: String { name }
    }

    enum State: Equatable {
        case idle
        case connecting(String)
        case connected(String)
        case lost(String)
    }

    private(set) var hosts: [Host] = []
    private(set) var state: State = .idle
    /// From the Mac: the game's controller type, speed and title.
    private(set) var controllerType: ControllerType = .classic2
    private(set) var speed = 1
    private(set) var gameTitle = ""

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var target: Host?
    private let queue = DispatchQueue(label: "ember.remote-client", qos: .userInteractive)

    private init() {}

    // MARK: - Finding Macs

    func browse() {
        guard browser == nil else { return }
        GameSender.usedBefore = true
        let browser = NWBrowser(for: .bonjour(type: RemoteProtocol.serviceType, domain: nil),
                                using: RemoteProtocol.parameters)
        browser.browseResultsChangedHandler = { results, _ in
            let found = results.compactMap { result -> Host? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return Host(name: name, endpoint: result.endpoint)
            }
            Task { @MainActor in RemoteControllerClient.shared.hosts = found.sorted { $0.name < $1.name } }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        hosts = []
    }

    // MARK: - Connecting

    func connect(to host: Host) {
        disconnect()
        target = host
        state = .connecting(host.name)
        let connection = NWConnection(to: host.endpoint, using: RemoteProtocol.parameters)
        connection.stateUpdateHandler = { state in
            Task { @MainActor in RemoteControllerClient.shared.connectionChanged(state, connection) }
        }
        RemoteProtocol.receive(on: connection, { kind, payload in
            Task { @MainActor in RemoteControllerClient.shared.received(kind, payload) }
        }, ended: {
            Task { @MainActor in RemoteControllerClient.shared.lost(connection) }
        })
        connection.start(queue: queue)
        self.connection = connection
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func disconnect() {
        send(.releaseAll)
        connection?.cancel()
        connection = nil
        target = nil
        state = .idle
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// After the link dropped (the Mac slept, the game ended): try again.
    func reconnect() {
        guard let target else { return }
        connect(to: target)
    }

    private func connectionChanged(_ new: NWConnection.State, _ source: NWConnection) {
        guard source === connection, let target else { return }
        switch new {
        case .ready:
            state = .connected(target.name)
            send(.hello, UIDevice.current.name)
        case .failed, .cancelled:
            if case .connected = state { state = .lost(target.name) }
            else if case .connecting = state { state = .lost(target.name) }
        case .waiting:
            state = .lost(target.name)
        default:
            break
        }
    }

    private func lost(_ source: NWConnection) {
        guard source === connection, let target else { return }
        state = .lost(target.name)
    }

    private func received(_ kind: RemoteProtocol.Kind, _ payload: String) {
        guard kind == .info else { return }
        let parts = payload.split(separator: "|", maxSplits: 2).map(String.init)
        if let type = parts.first.flatMap(ControllerType.init(rawValue:)) { controllerType = type }
        if parts.count > 1, let value = Int(parts[1]) { speed = value }
        if parts.count > 2 { gameTitle = parts[2] }
    }

    // MARK: - Sending

    func send(_ kind: RemoteProtocol.Kind, _ payload: String = "") {
        guard let connection else { return }
        connection.send(content: RemoteProtocol.encode(kind, payload), completion: .contentProcessed { _ in })
    }

    func press(_ button: ControlButton) {
        Haptics.tap()
        send(.buttonDown, button.rawValue)
    }

    func release(_ button: ControlButton) {
        send(.buttonUp, button.rawValue)
    }

    func press(_ direction: ControlDirection) {
        send(.directionDown, direction.rawValue)
    }

    func release(_ direction: ControlDirection) {
        send(.directionUp, direction.rawValue)
    }

    func command(_ command: RemoteProtocol.Command, _ argument: String? = nil) {
        send(.command, argument.map { "\(command.rawValue):\($0)" } ?? command.rawValue)
    }

    #if DEBUG
    /// Development aid: EMBER_REMOTE="seconds:button[:down|up],…" connects
    /// to the first Mac found, opens the controller and taps buttons
    /// (a, b, start, select, l, r) and directions (up, down, left, right).
    func runDevelopmentScript(_ script: String) {
        browse()
        Task { @MainActor in
            while hosts.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            connect(to: hosts[0])
            RemoteControllerScreen.present()
            for step in script.split(separator: ",") {
                let parts = step.split(separator: ":").map(String.init)
                guard parts.count >= 2, let seconds = Double(parts[0]) else { continue }
                try? await Task.sleep(for: .seconds(seconds))
                if let button = ControlButton(rawValue: parts[1]) {
                    press(button)
                    try? await Task.sleep(for: .milliseconds(120))
                    release(button)
                } else if let direction = ControlDirection(rawValue: parts[1]) {
                    press(direction)
                    try? await Task.sleep(for: .milliseconds(180))
                    release(direction)
                }
                print("[ember-remote] \(parts[1]) \(state)")
            }
        }
    }
    #endif
}
