import Foundation
import SwiftUI
@preconcurrency import Translation

/// "Traduzir textos" for one game: the game's messages, translated on
/// the device by Apple's Translation framework (iOS 26+), from the
/// language the player picks to the iPhone's language. The game side is
/// ember_translate.rb; the two talk through files in
/// Application Support/Translations/<game id>/ (req/ and out/). Answers
/// stay there, so a line is translated once.
enum GameTranslation {
    private static let key = "translation.sourceByGame"

    /// Languages fan games are often made in.
    static let sources: [(code: String, name: LocalizedStringResource)] = [
        ("ja", "Japonês"), ("en", "Inglês"), ("es", "Espanhol"), ("pt", "Português"),
        ("zh-Hans", "Chinês"), ("ko", "Coreano"), ("fr", "Francês"), ("de", "Alemão"),
        ("it", "Italiano"), ("ru", "Russo"),
    ]

    static var isSupported: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    /// The language the game is translated from, or nil when off.
    static func source(for id: String) -> String? {
        #if DEBUG
        // Development aid: EMBER_TRANSLATE=<language> turns it on for
        // every game.
        if let code = ProcessInfo.processInfo.environment["EMBER_TRANSLATE"] { return code }
        #endif
        return (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?[id]
    }

    static func setSource(_ code: String?, for id: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        all[id] = code
        UserDefaults.standard.set(all, forKey: key)
    }

    static var target: Locale.Language {
        Locale.current.language
    }

    static func folder(for id: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Translations/\(id)", isDirectory: true)
    }

    /// Before the engine starts: tells the game script where to ask.
    static func prepareEnvironment(for game: GameEntry) {
        guard isSupported, source(for: game.id) != nil else {
            unsetenv("EMBER_TRANSLATE_DIR")
            return
        }
        let folder = folder(for: game.id)
        for sub in ["req", "out"] {
            try? FileManager.default.createDirectory(at: folder.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        setenv("EMBER_TRANSLATE_DIR", folder.path, 1)
    }

    /// Lines already translated for the game.
    static func cachedCount(for id: String) -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder(for: id).appendingPathComponent("out").path)) ?? []).count
    }

    static func clearCache(for id: String) {
        try? FileManager.default.removeItem(at: folder(for: id))
    }
}

/// Answers the game's translation requests while it runs.
@available(iOS 26, *)
@MainActor
final class TranslationWorker {
    static var current: TranslationWorker?

    private let session: TranslationSession
    private let requests: URL
    private let answers: URL
    private var watcher: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1
    private var working: Set<String> = []

    private init(session: TranslationSession, folder: URL) {
        self.session = session
        requests = folder.appendingPathComponent("req")
        answers = folder.appendingPathComponent("out")
    }

    /// Starts for the game when its translation is on and the languages
    /// are on the device.
    static func start(for game: GameEntry) {
        stop()
        guard let code = GameTranslation.source(for: game.id) else { return }
        let source = Locale.Language(identifier: code)
        let target = GameTranslation.target
        guard source.languageCode != target.languageCode else { return }
        let worker = TranslationWorker(session: TranslationSession(installedSource: source, target: target),
                                       folder: GameTranslation.folder(for: game.id))
        worker.watch()
        current = worker
        GameLog.shared.note("tradução ligada: \(code) → \(target.minimalIdentifier)")
    }

    static func stop() {
        current?.watcher?.cancel()
        current = nil
    }

    private func watch() {
        descriptor = open(requests.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        let fd = descriptor
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
        scan()
    }

    private func scan() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: requests.path)) ?? []
        for name in names where name.hasSuffix(".txt") && !working.contains(name) {
            working.insert(name)
            let request = requests.appendingPathComponent(name)
            let answer = answers.appendingPathComponent(name)
            Task {
                defer { working.remove(name) }
                guard let text = try? String(contentsOf: request, encoding: .utf8) else { return }
                do {
                    let translated = try await session.translate(text).targetText
                    try? translated.write(to: answer, atomically: true, encoding: .utf8)
                } catch {
                    GameLog.shared.note("tradução falhou: \(error.localizedDescription)")
                    // The game shows the original rather than waiting,
                    // but it is not kept: once the languages are on the
                    // device the line gets translated.
                    try? text.write(to: answer, atomically: true, encoding: .utf8)
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        try? FileManager.default.removeItem(at: answer)
                    }
                }
                try? FileManager.default.removeItem(at: request)
            }
        }
    }
}

/// Painel do jogo › Traduzir textos.
@available(iOS 26, *)
struct GameTranslationView: View {
    let game: GameEntry
    @Environment(\.dismiss) private var dismiss
    @State private var source: String?
    @State private var status: String?
    @State private var cached = 0
    @State private var preparing: TranslationSession.Configuration?

    init(game: GameEntry) {
        self.game = game
        _source = State(initialValue: GameTranslation.source(for: game.id))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Idioma do jogo", selection: $source) {
                        Text("Sem tradução").tag(String?.none)
                        ForEach(GameTranslation.sources, id: \.code) { language in
                            Text(language.name).tag(String?.some(language.code))
                        }
                    }
                    if let status {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } footer: {
                    Text("As falas do jogo aparecem no idioma do iPhone. A tradução é feita no próprio aparelho pela Apple, sem internet depois de baixar os idiomas, e cada fala é traduzida uma vez só. Menus e imagens com texto continuam no original.")
                }
                if cached > 0 {
                    Section {
                        Button("Apagar as traduções guardadas (\(cached))", role: .destructive) {
                            GameTranslation.clearCache(for: game.id)
                            cached = 0
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Traduzir textos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .onChange(of: source) {
                GameTranslation.setSource(source, for: game.id)
                Task { await checkLanguages() }
            }
            .task {
                cached = GameTranslation.cachedCount(for: game.id)
                await checkLanguages()
            }
            // Asks iOS to download the languages when they are missing.
            .translationTask(preparing) { session in
                do {
                    try await session.prepareTranslation()
                    await checkLanguages()
                } catch {
                    status = String(localized: "Os idiomas não foram baixados. Tente de novo ou baixe em Ajustes › Apps › Traduzir.")
                }
            }
        }
    }

    private func checkLanguages() async {
        guard let source else { status = nil; return }
        let from = Locale.Language(identifier: source)
        let to = GameTranslation.target
        if from.languageCode == to.languageCode {
            status = String(localized: "O jogo já está no idioma do iPhone.")
            return
        }
        switch await LanguageAvailability().status(from: from, to: to) {
        case .installed:
            status = String(localized: "Pronto. Vale na próxima vez que o jogo abrir.")
        case .supported:
            status = String(localized: "Baixando os idiomas…")
            preparing = TranslationSession.Configuration(source: from, target: to)
        case .unsupported:
            status = String(localized: "A Apple ainda não traduz entre esses idiomas.")
        @unknown default:
            status = nil
        }
    }
}
