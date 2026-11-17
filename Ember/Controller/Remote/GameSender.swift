import Foundation
import Network
import Observation
import SwiftUI
import UIKit

/// "Enviar jogos para o Mac": finds Ember on a Mac nearby and sends the
/// games the player picks, file by file, with their saves and save
/// states. The Mac asks its user before taking anything.
@MainActor
@Observable
final class GameSender {
    static let shared = GameSender()

    struct Mac: Identifiable, Hashable {
        let name: String
        let endpoint: NWEndpoint
        var id: String { name }
    }

    enum State: Equatable {
        case idle
        case waitingForMac
        case sending(title: String, fraction: Double)
        case done([String])
        case declined
        case failed(String)
    }

    private(set) var macs: [Mac] = []
    private(set) var state: State = .idle
    /// Has the player used a Mac link before (so browsing won't bring up
    /// the local network permission out of nowhere)?
    static var usedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: "remote.usedLocalNetwork") }
        set { UserDefaults.standard.set(newValue, forKey: "remote.usedLocalNetwork") }
    }

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "ember.game-sender", qos: .userInitiated)

    private init() {}

    func browse() {
        guard browser == nil else { return }
        Self.usedBefore = true
        let browser = NWBrowser(for: .bonjour(type: TransferProtocol.serviceType, domain: nil),
                                using: TransferProtocol.parameters)
        browser.browseResultsChangedHandler = { results, _ in
            let found = results.compactMap { result -> Mac? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return Mac(name: name, endpoint: result.endpoint)
            }
            Task { @MainActor in GameSender.shared.macs = found.sorted { $0.name < $1.name } }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        macs = []
    }

    func reset() {
        if case .sending = state { return }
        state = .idle
    }

    func cancel() {
        connection?.cancel()
        connection = nil
        state = .failed(String(localized: "Envio cancelado. Os jogos que chegaram inteiros ficaram no Mac."))
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// The size of what a game sends: its folder, saves and states.
    nonisolated static func size(of game: GameEntry) -> Int64 {
        files(of: game).reduce(0) { $0 + $1.size }
    }

    // MARK: - Sending

    func send(_ games: [GameEntry], to mac: Mac) {
        state = .waitingForMac
        UIApplication.shared.isIdleTimerDisabled = true
        let connection = NWConnection(to: mac.endpoint, using: TransferProtocol.parameters)
        self.connection = connection
        connection.start(queue: queue)
        Task.detached(priority: .userInitiated) {
            let offer = TransferProtocol.Offer(
                device: await UIDevice.current.name,
                games: games.map { .init(id: $0.id, title: $0.title, bytes: Self.size(of: $0)) })
            let result = await Self.run(offer, games: games, on: connection)
            await MainActor.run {
                UIApplication.shared.isIdleTimerDisabled = false
                guard GameSender.shared.connection === connection else { return }
                GameSender.shared.state = result
                GameSender.shared.connection = nil
            }
        }
    }

    private nonisolated static func run(_ offer: TransferProtocol.Offer, games: [GameEntry],
                                        on connection: NWConnection) async -> State {
        guard await send(connection, TransferProtocol.encode(.offer, json: offer)) else {
            return .failed(String(localized: "Não deu para falar com o Mac. Confira se o Ember está aberto nele."))
        }
        let (kind, data) = await receive(connection)
        guard kind == .answer, let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return .failed(String(localized: "O Mac não respondeu."))
        }
        guard !ids.isEmpty else {
            connection.cancel()
            return .declined
        }
        let taken = games.filter { ids.contains($0.id) }
        let total = max(1, offer.games.filter { ids.contains($0.id) }.reduce(0) { $0 + $1.bytes })
        var sent: Int64 = 0
        var lastReport = Date.distantPast
        for game in taken {
            for file in files(of: game) {
                let header = TransferProtocol.FileHeader(id: game.id, area: file.area, path: file.path,
                                                         size: file.size, modified: file.modified)
                guard await send(connection, TransferProtocol.encode(.file, json: header)),
                      let handle = try? FileHandle(forReadingFrom: file.url)
                else { return .failed(String(localized: "O envio parou. Os jogos que chegaram inteiros ficaram no Mac.")) }
                defer { try? handle.close() }
                while let chunk = try? handle.read(upToCount: TransferProtocol.chunkSize), !chunk.isEmpty {
                    guard await send(connection, TransferProtocol.encode(.chunk, chunk)) else {
                        return .failed(String(localized: "O envio parou. Os jogos que chegaram inteiros ficaram no Mac."))
                    }
                    sent += Int64(chunk.count)
                    if Date().timeIntervalSince(lastReport) > 0.2 {
                        lastReport = Date()
                        let fraction = Double(sent) / Double(total)
                        let title = game.title
                        await MainActor.run { GameSender.shared.state = .sending(title: title, fraction: fraction) }
                    }
                }
            }
            _ = await send(connection, TransferProtocol.encode(.gameDone, Data(game.id.utf8)))
        }
        _ = await send(connection, TransferProtocol.encode(.done))
        // Let the last bytes reach the Mac before closing.
        try? await Task.sleep(for: .seconds(1))
        connection.cancel()
        return .done(taken.map(\.title))
    }

    private nonisolated static func send(_ connection: NWConnection, _ data: Data) async -> Bool {
        await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                continuation.resume(returning: error == nil)
            })
        }
    }

    private nonisolated static func receive(_ connection: NWConnection) async -> (TransferProtocol.Kind?, Data) {
        await withCheckedContinuation { continuation in
            TransferProtocol.receiveOne(on: connection) { kind, data in
                continuation.resume(returning: (kind, data))
            }
        }
    }

    // MARK: - What a game sends

    struct File {
        let area: TransferProtocol.Area
        let path: String
        let url: URL
        let size: Int64
        let modified: Date
    }

    private nonisolated static func files(of game: GameEntry) -> [File] {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let areas: [(TransferProtocol.Area, URL)] = [
            (.game, game.folder),
            (.userData, documents.appendingPathComponent("UserData/\(game.id)")),
            (.states, support.appendingPathComponent("States/\(game.id)")),
        ]
        var result: [File] = []
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        // The cover the shelf shows: the last frame, or the player's pick.
        for name in ["\(game.id).jpg", "\(game.id)-custom.jpg"] {
            let url = support.appendingPathComponent("Covers/\(name)")
            if let values = try? url.resourceValues(forKeys: keys), values.isDirectory != true {
                result.append(File(area: .covers, path: name, url: url, size: Int64(values.fileSize ?? 0),
                                   modified: values.contentModificationDate ?? Date()))
            }
        }
        for (area, folder) in areas {
            guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) else { continue }
            let base = folder.standardizedFileURL.path
            for case let url as URL in walker {
                guard let values = try? url.resourceValues(forKeys: keys), values.isDirectory != true else { continue }
                let path = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
                // The request files Ember and the game trade while it runs.
                if area == .states, ["request", "response", "thumb_request", "cheat_request", "filter_request"].contains(path) { continue }
                result.append(File(area: area, path: path, url: url, size: Int64(values.fileSize ?? 0),
                                   modified: values.contentModificationDate ?? Date()))
            }
        }
        return result
    }
}

/// Library › Enviar jogos para o Mac.
struct SendToMacView: View {
    @Bindable private var sender = GameSender.shared
    @Bindable private var library = LibraryStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var mac: GameSender.Mac?
    @State private var sizes: [String: Int64] = [:]

    var body: some View {
        NavigationStack {
            Group {
                switch sender.state {
                case .idle:
                    picker
                case .waitingForMac:
                    status(icon: "macbook", title: String(localized: "Aguardando o Mac"),
                           detail: String(localized: "Aceite o envio na tela do Mac."), progress: nil)
                case .sending(let title, let fraction):
                    status(icon: "arrow.up.circle", title: String(localized: "Enviando \(title)"),
                           detail: fraction.formatted(.percent.precision(.fractionLength(0))), progress: fraction)
                case .done(let titles):
                    status(icon: "checkmark.circle.fill", title: String(localized: "Enviado"),
                           detail: titles.joined(separator: ", "), progress: nil)
                case .declined:
                    status(icon: "xmark.circle", title: String(localized: "O Mac recusou o envio"), detail: "", progress: nil)
                case .failed(let message):
                    status(icon: "exclamationmark.triangle", title: String(localized: "Não deu certo"), detail: message, progress: nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Enviar jogos para o Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .sending = sender.state {
                        Button("Cancelar envio", role: .destructive) { sender.cancel() }
                    } else {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Fechar")
                    }
                }
            }
            .onAppear {
                sender.reset()
                sender.browse()
            }
            .task {
                let games = library.games
                let found = await Task.detached(priority: .utility) {
                    Dictionary(uniqueKeysWithValues: games.map { ($0.id, GameSender.size(of: $0)) })
                }.value
                sizes = found
            }
        }
    }

    private var picker: some View {
        List {
            Section {
                if sender.macs.isEmpty {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Procurando o Ember num Mac por perto…").foregroundStyle(Theme.secondaryText)
                    }
                }
                ForEach(sender.macs) { found in
                    Button {
                        mac = found
                    } label: {
                        HStack {
                            Label(found.name, systemImage: "macbook").foregroundStyle(Theme.primaryText)
                            Spacer()
                            if mac == found || (mac == nil && sender.macs.count == 1) {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            } header: {
                Text("Mac")
            } footer: {
                Text("Abra o Ember no Mac. Não precisa estar no mesmo Wi-Fi.")
            }

            Section {
                ForEach(library.games) { game in
                    Button {
                        if picked.contains(game.id) { picked.remove(game.id) } else { picked.insert(game.id) }
                    } label: {
                        HStack {
                            Image(systemName: picked.contains(game.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(picked.contains(game.id) ? Theme.accent : Theme.secondaryText)
                            Text(game.title).foregroundStyle(Theme.primaryText)
                            Spacer()
                            if let size = sizes[game.id] {
                                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                }
            } header: {
                Text("Jogos")
            } footer: {
                Text("Cada jogo vai com os saves e os estados salvos. Depois, os saves continuam iguais nos dois pelo iCloud.")
            }

            Section {
                Button {
                    guard let target = mac ?? (sender.macs.count == 1 ? sender.macs.first : nil) else { return }
                    sender.send(library.games.filter { picked.contains($0.id) }, to: target)
                } label: {
                    Text(picked.count == 1 ? String(localized: "Enviar 1 jogo") : String(localized: "Enviar \(picked.count) jogos"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(picked.isEmpty || (mac == nil && sender.macs.count != 1))
                .listRowBackground(Color.clear)
            }
        }
    }

    private func status(icon: String, title: String, detail: String, progress: Double?) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
            if let progress {
                ProgressView(value: progress).frame(maxWidth: 260)
            }
            if !detail.isEmpty {
                Text(detail)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            if case .sending = sender.state {
                Text("Deixe o Ember aberto até terminar.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else if progress == nil, sender.state != .waitingForMac {
                Button("Enviar outros jogos") { sender.reset() }
                    .padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
