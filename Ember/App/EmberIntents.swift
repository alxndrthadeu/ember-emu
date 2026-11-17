import AppIntents

/// Siri, Spotlight and the Shortcuts app: continue the last game, play
/// a game from the shelf, import, or start the Wi-Fi transfer. Each one
/// opens Ember and goes through the same path as the icon's quick
/// actions.

struct ContinueGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Continuar o último jogo"
    static let description = IntentDescription("Abre o Ember no último jogo, de onde você parou.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.quickAction = .continueLast
        return .result()
    }
}

struct PlayGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Jogar"
    static let description = IntentDescription("Abre um jogo da sua estante no Ember.")
    static let openAppWhenRun = true

    @Parameter(title: "Jogo")
    var game: GameAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Jogar \(\.$game)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.gameToOpen = game.id
        return .result()
    }
}

struct ImportGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Importar um jogo"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.quickAction = .importGame
        return .result()
    }
}

struct WifiTransferIntent: AppIntent {
    static let title: LocalizedStringResource = "Enviar jogos pelo Wi-Fi"
    static let description = IntentDescription("Abre o Ember com a transferência pelo navegador ligada.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.quickAction = .wifi
        return .result()
    }
}

/// A game on the shelf, for Siri and Shortcuts.
struct GameAppEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Jogo"
    static let defaultQuery = GameQuery()

    let id: String
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct GameQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [GameAppEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [GameAppEntity] {
        all().filter { $0.title.localizedStandardContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [GameAppEntity] {
        all()
    }

    @MainActor
    private func all() -> [GameAppEntity] {
        LibraryStore.shared.games.map { GameAppEntity(id: $0.id, title: $0.title) }
    }
}

struct EmberShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ContinueGameIntent(),
                    phrases: ["Continuar no \(.applicationName)", "Continue in \(.applicationName)",
                              "Continuar mi juego en \(.applicationName)"],
                    shortTitle: "Continuar", systemImageName: "play.fill")
        AppShortcut(intent: PlayGameIntent(),
                    phrases: ["Jogar \(\.$game) no \(.applicationName)", "Play \(\.$game) in \(.applicationName)",
                              "Jugar \(\.$game) en \(.applicationName)"],
                    shortTitle: "Jogar", systemImageName: "gamecontroller.fill")
        AppShortcut(intent: WifiTransferIntent(),
                    phrases: ["Enviar jogos para o \(.applicationName)", "Send games to \(.applicationName)"],
                    shortTitle: "Wi-Fi", systemImageName: "wifi")
    }
}
