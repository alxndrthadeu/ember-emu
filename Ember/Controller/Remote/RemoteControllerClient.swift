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

    /// The link's round trip, from the pings (nil before the first).
    private(set) var latency: Duration?
    /// Whether the link went over the direct, AirDrop-like path.
    private(set) var direct = false
    /// A message from the Mac, shown for a few seconds.
    private(set) var notice: String?

    private var retries = 0
    private var attempt = 0
    private var lastPong = Date()
    private var pinger: Task<Void, Never>?

    func connect(to host: Host) {
        disconnect()
        profileSentFor = nil
        retries = 0
        target = host
        state = .connecting(host.name)
        UIApplication.shared.isIdleTimerDisabled = true
        open(host, peerToPeer: false)
    }

    /// The normal network first; the direct link if it does not answer
    /// within a couple of seconds (not on the same Wi-Fi).
    private func open(_ host: Host, peerToPeer: Bool) {
        connection?.cancel()
        attempt += 1
        let thisAttempt = attempt
        direct = peerToPeer
        let connection = NWConnection(to: host.endpoint, using: RemoteProtocol.parameters(peerToPeer: peerToPeer))
        connection.stateUpdateHandler = { state in
            Task { @MainActor in RemoteControllerClient.shared.connectionChanged(state, connection) }
        }
        RemoteProtocol.receive(on: connection, { kind, payload in
            Task { @MainActor in RemoteControllerClient.shared.received(kind, payload) }
        }, ended: {
            Task { @MainActor in RemoteControllerClient.shared.dropped(connection, reason: "fim da conexão") }
        })
        connection.start(queue: queue)
        self.connection = connection
        guard !peerToPeer else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard self.attempt == thisAttempt, case .connecting = self.state, self.target == host else { return }
            self.open(host, peerToPeer: true)
        }
    }

    func disconnect() {
        send(.releaseAll)
        pinger?.cancel()
        pinger = nil
        connection?.cancel()
        connection = nil
        target = nil
        latency = nil
        state = .idle
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// After the link dropped (the Mac slept, the game ended): try again.
    func reconnect() {
        guard let target else { return }
        retries = 0
        state = .connecting(target.name)
        open(target, peerToPeer: false)
    }

    private func connectionChanged(_ new: NWConnection.State, _ source: NWConnection) {
        #if DEBUG
        print("[ember-remote] connection \(new) direct=\(direct)")
        #endif
        guard source === connection, let target else { return }
        switch new {
        case .ready:
            retries = 0
            state = .connected(target.name)
            send(.hello, UIDevice.current.name)
            startPinging(source)
        case .failed(let error):
            dropped(source, reason: error.localizedDescription)
        case .waiting:
            // Network.framework keeps trying; open() moves on to the
            // direct link if this takes long.
            if case .connected = state { state = .connecting(target.name) }
        default:
            break
        }
    }

    /// The link went away: try again by ourselves a few times, then let
    /// the player tap Reconectar.
    private func dropped(_ source: NWConnection, reason: String) {
        guard source === connection, let target else { return }
        pinger?.cancel()
        latency = nil
        #if DEBUG
        print("[ember-remote] dropped: \(reason)")
        #endif
        if retries < 4 {
            retries += 1
            state = .connecting(target.name)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                guard self.target == target, case .connecting = self.state else { return }
                self.open(target, peerToPeer: false)
            }
        } else {
            state = .lost(target.name)
        }
    }

    /// A ping a second keeps the link (and the direct radio) awake and
    /// measures the delay; four seconds without an answer means the link
    /// is gone even if no one said so.
    private func startPinging(_ source: NWConnection) {
        pinger?.cancel()
        lastPong = Date()
        pinger = Task { @MainActor in
            while !Task.isCancelled, source === self.connection {
                self.send(.ping, String(Date().timeIntervalSince1970))
                try? await Task.sleep(for: .seconds(1))
                if Date().timeIntervalSince(self.lastPong) > 4 {
                    source.cancel()
                    self.dropped(source, reason: "sem resposta do Mac")
                    return
                }
            }
        }
    }

    private func received(_ kind: RemoteProtocol.Kind, _ payload: String) {
        if kind == .pong {
            lastPong = Date()
            if let sent = Double(payload) {
                latency = .milliseconds(Int((Date().timeIntervalSince1970 - sent) * 1000))
            }
            return
        }
        if kind == .notice {
            notice = payload
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if notice == payload { notice = nil }
            }
            return
        }
        guard kind == .info else { return }
        let parts = payload.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        if let type = parts.first.flatMap(ControllerType.init(rawValue:)) { controllerType = type }
        if parts.count > 1, let value = Int(parts[1]) { speed = value }
        if parts.count > 3 {
            gameTitle = parts[3]
            sendProfile(forGameID: parts[2])
        }
    }

    // MARK: - Sending

    /// The controls this iPhone uses for the game (its own mapping, or
    /// its profile), when the game is on this iPhone too. Sent once per
    /// game: the Mac then plays every button the same way.
    private var profileSentFor: String?

    private func sendProfile(forGameID id: String) {
        guard profileSentFor != id,
              let game = LibraryStore.shared.games.first(where: { $0.id == id }),
              let data = try? JSONEncoder().encode(ProfileStore.shared.profile(for: game))
        else { return }
        profileSentFor = id
        send(.profile, String(decoding: data, as: UTF8.self))
    }

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
                    // A quick tap, as a thumb does it.
                    press(button)
                    try? await Task.sleep(for: .milliseconds(30))
                    release(button)
                } else if let direction = ControlDirection(rawValue: parts[1]) {
                    press(direction)
                    try? await Task.sleep(for: .milliseconds(180))
                    release(direction)
                }
                print("[ember-remote] \(parts[1]) \(state) latency \(latency.map { "\($0)" } ?? "?") direct \(direct)")
            }
        }
    }
    #endif
}
