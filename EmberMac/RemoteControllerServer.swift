import AppKit
import Network

/// The game instance's side of "iPhone as controller": advertises the
/// game nearby and plays what an iPhone sends, through the game's
/// control profile (ControlMapper), as the iPhone app does with its own
/// buttons. One iPhone at a time; a new one takes over.
@MainActor
final class RemoteControllerServer {
    static let shared = RemoteControllerServer()

    /// The connected iPhone's name, or nil.
    private(set) var connectedName: String?
    var onChange: () -> Void = {}

    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "ember.remote-controller", qos: .userInteractive)

    private init() {}

    func start(for game: GameEntry) {
        guard listener == nil else { return }
        ControlMapper.shared.profile = ProfileStore.shared.profile(for: game)
        do {
            let listener = try NWListener(using: RemoteProtocol.parameters)
            let mac = Host.current().localizedName ?? "Mac"
            // "<Mac> · <game>": what the iPhone lists.
            listener.service = NWListener.Service(name: String("\(mac) · \(game.title)".prefix(63)),
                                                  type: RemoteProtocol.serviceType)
            listener.newConnectionHandler = { connection in
                onMainRunLoop { RemoteControllerServer.shared.accept(connection) }
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    onMainRunLoop { GameLog.shared.note("controle remoto: \(error.localizedDescription)") }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            GameLog.shared.note("controle remoto: \(error.localizedDescription)")
        }
    }

    func stop() {
        connection?.cancel()
        listener?.cancel()
        listener = nil
        connection = nil
    }

    private func accept(_ new: NWConnection) {
        // The newest iPhone wins: an old link may be stale.
        connection?.cancel()
        ControlMapper.shared.releaseAll()
        connection = new
        new.start(queue: queue)
        RemoteProtocol.receive(on: new, { kind, payload in
            onMainRunLoop { RemoteControllerServer.shared.handle(kind, payload, from: new) }
        }, ended: {
            onMainRunLoop { RemoteControllerServer.shared.ended(new) }
        })
        sendInfo()
    }

    private func ended(_ old: NWConnection) {
        guard old === connection else { return }
        ControlMapper.shared.releaseAll()
        connection = nil
        if let name = connectedName { GameLog.shared.note("controle remoto desconectado: \(name)") }
        connectedName = nil
        onChange()
    }

    private func handle(_ kind: RemoteProtocol.Kind, _ payload: String, from source: NWConnection) {
        guard source === connection else { return }
        let mapper = ControlMapper.shared
        switch kind {
        case .hello:
            connectedName = payload.isEmpty ? "iPhone" : payload
            GameLog.shared.note("controle remoto conectado: \(connectedName ?? "")")
            onChange()
        case .buttonDown:
            if let button = ControlButton(rawValue: payload) { mapper.press(button) }
        case .buttonUp:
            if let button = ControlButton(rawValue: payload) { mapper.release(button) }
        case .directionDown:
            if let direction = ControlDirection(rawValue: payload) { mapper.press(direction) }
        case .directionUp:
            if let direction = ControlDirection(rawValue: payload) { mapper.release(direction) }
        case .text:
            for character in payload { KeyTapper.type(character) }
        case .key:
            KeyTapper.tap(payload == "backspace" ? .backspace : .enter)
        case .command:
            command(payload)
        case .releaseAll:
            mapper.releaseAll()
        case .info:
            break
        }
    }

    private func command(_ text: String) {
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        switch RemoteProtocol.Command(rawValue: parts.first ?? "") {
        case .saveState:
            Task { _ = await EngineSession.shared.requestState("save", slot: StateStore.newSlot()) }
        case .loadState:
            guard let game = EngineSession.shared.currentGame,
                  let last = StateStore.states(for: game.id).first else { return }
            Task { _ = await EngineSession.shared.requestState("load", slot: last.slot) }
        case .cheats:
            Task { await CheatMenu.open() }
        case .quit:
            EngineSession.shared.quit()
        case .speed:
            if let value = parts.dropFirst().first.flatMap(Int.init) {
                GameSettings.speed = value
                GameSettings.apply()
                sendInfo()
            }
        case nil:
            break
        }
    }

    /// Tells the iPhone which controller the game wants and its name.
    private func sendInfo() {
        guard let connection, let game = EngineSession.shared.currentGame else { return }
        let type = ControllerTypeStore.type(for: game).rawValue
        let message = "\(type)|\(GameSettings.speed)|\(game.title)"
        connection.send(content: RemoteProtocol.encode(.info, message), completion: .contentProcessed { _ in })
    }
}
