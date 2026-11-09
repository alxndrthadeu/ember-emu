import Foundation

/// How the game picture is scaled up to the screen: the engine's own
/// scaling modes (smoothScaling in mkxp-z).
enum ScreenFilter: Int, CaseIterable, Identifiable {
    /// Hard pixel edges (nearest neighbor), as on a PC at 2x.
    case pixel = 0
    /// Soft (bilinear).
    case smooth = 1
    /// Sharp but smooth (Lanczos).
    case sharp = 3
    // xBRZ (4) is left out: the iOS engine is built without its shader.

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .pixel: String(localized: "Pixel")
        case .smooth: String(localized: "Suave")
        case .sharp: String(localized: "Nítido")
        }
    }

    var detail: String {
        switch self {
        case .pixel: String(localized: "Pixels retos, como no PC.")
        case .smooth: String(localized: "Imagem suavizada.")
        case .sharp: String(localized: "Suave nas bordas, sem perder detalhe.")
        }
    }

    var next: ScreenFilter {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    private static let key = "settings.screenFilter"

    static var current: ScreenFilter {
        get { ScreenFilter(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .pixel }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// Engine config for a session (EngineConfig's overlay).
    static var overlay: [String: Any] {
        ["smoothScaling": current.rawValue]
    }

    /// Changes the filter of the running game (ember_quicksave.rb reads
    /// the request on the next tick).
    @MainActor
    static func apply(_ filter: ScreenFilter) {
        current = filter
        guard let game = EngineSession.shared.currentGame else { return }
        let request = StateStore.folder(for: game.id).appendingPathComponent("filter_request")
        try? Data("\(filter.rawValue)".utf8).write(to: request)
    }
}
