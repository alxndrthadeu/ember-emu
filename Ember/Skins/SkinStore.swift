import Foundation
import ZIPFoundation

/// The skins Ember knows: its own and the ones the player imported,
/// and which one is in use.
@MainActor
final class SkinStore: ObservableObject {
    static let shared = SkinStore()

    @Published private(set) var imported: [Skin] = []
    @Published var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: Self.selectedKey) }
    }

    private static let selectedKey = "skins.selected"

    var all: [Skin] { BuiltInSkins.all + imported }

    var current: Skin {
        all.first { $0.id == selectedID } ?? BuiltInSkins.ember
    }

    /// The layout for an orientation. A skin without that orientation
    /// falls back to Ember Laranja's. `keyboard`: the game needs the
    /// keyboard button (built-in skins draw it next to the gear).
    /// The controller type of the game being played (Clássico 2 botões
    /// outside a game).
    var controllerType: ControllerType {
        EngineSession.shared.currentGame.map(ControllerTypeStore.type(for:)) ?? .classic2
    }

    /// The skin on screen (ControllerLayouts.effectiveSkin).
    var effectiveSkin: Skin {
        ControllerLayouts.effectiveSkin(current, type: controllerType)
    }

    /// The layout of the game screen now (ControllerLayouts has the rules).
    func layout(portrait: Bool, keyboard: Bool = false) -> SkinLayout {
        let context = ControllerContext.current(portrait: portrait, keyboard: keyboard, type: controllerType)
        return ControllerLayouts.layout(for: effectiveSkin, in: context)
    }

    /// Built-in skins in portrait: the game across the full width, no
    /// frame (the default: the biggest picture), or in a thin frame.
    @Published var portraitFullWidth = (UserDefaults.standard.object(forKey: "settings.portraitFullWidth") as? Bool ?? true) {
        didSet { UserDefaults.standard.set(portraitFullWidth, forKey: "settings.portraitFullWidth") }
    }

    /// iPhone Duo unfolded: game and controller on separate halves
    /// (true) or one big picture with the controller around it.
    @Published var duoSplit = (UserDefaults.standard.object(forKey: "settings.duoSplit") as? Bool ?? true) {
        didSet { UserDefaults.standard.set(duoSplit, forKey: "settings.duoSplit") }
    }

    /// iPhone Duo DS layout: the game on the bottom window instead of
    /// the top screen.
    @Published var duoGameBelow = UserDefaults.standard.bool(forKey: "settings.duoGameBelow") {
        didSet { UserDefaults.standard.set(duoGameBelow, forKey: "settings.duoGameBelow") }
    }

    private init() {
        selectedID = UserDefaults.standard.string(forKey: Self.selectedKey) ?? BuiltInSkins.ember.id
        reload()
        #if DEBUG
        // Development aid: EMBER_SKIN=<id> picks a skin at launch.
        if let id = ProcessInfo.processInfo.environment["EMBER_SKIN"] { selectedID = id }
        #endif
    }

    static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Skins", isDirectory: true)
    }

    func reload() {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: Self.folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        imported = folders
            .compactMap { try? SkinParser.parse(folder: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Imports a .deltaskin / .manicskin (zip) or an unpacked skin
    /// folder, and selects it. A skin with the same identifier is
    /// replaced.
    @discardableResult
    func importSkin(from url: URL) throws -> Skin {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("Skin-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let unpacked = work.appendingPathComponent("skin")
        if isFolder {
            try fm.copyItem(at: url, to: unpacked)
        } else {
            try fm.unzipItem(at: url, to: unpacked)
        }
        GameImporter.removeMacMetadata(in: unpacked)

        // Some archives wrap the skin in one more folder.
        let root = findInfo(in: unpacked) ?? unpacked
        let parsed = try SkinParser.parse(folder: root)

        try fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let safe = parsed.id.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        let target = Self.folder.appendingPathComponent(safe, isDirectory: true)
        try? fm.removeItem(at: target)
        try fm.moveItem(at: root, to: target)

        reload()
        let skin = try SkinParser.parse(folder: target)
        selectedID = skin.id
        return skin
    }

    func delete(_ skin: Skin) {
        guard case .imported(let folder) = skin.source else { return }
        try? FileManager.default.removeItem(at: folder)
        if selectedID == skin.id { selectedID = BuiltInSkins.ember.id }
        reload()
    }

    private func findInfo(in folder: URL, depth: Int = 2) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.appendingPathComponent("info.json").path) { return folder }
        guard depth > 0 else { return nil }
        let children = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if let found = findInfo(in: child, depth: depth - 1) { return found }
        }
        return nil
    }

    /// File extensions that are skins.
    static let skinExtensions: Set<String> = ["deltaskin", "manicskin"]
}

/// Settings from the Ajustes tab.
enum AppSettings {
    private static let defaults = UserDefaults.standard

    /// Light taps on button presses.
    static var haptics: Bool {
        get { defaults.object(forKey: "settings.haptics") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "settings.haptics") }
    }

    /// How opaque the controller is in landscape, over the game, for
    /// skins that allow it.
    static var landscapeOpacity: Double {
        get { defaults.object(forKey: "settings.landscapeOpacity") as? Double ?? 0.8 }
        set { defaults.set(newValue, forKey: "settings.landscapeOpacity") }
    }

    /// Hide the on-screen buttons in landscape while a controller is
    /// connected.
    static var hideControlsWithController: Bool {
        get { defaults.object(forKey: "settings.hideWithController") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "settings.hideWithController") }
    }

    /// The speed a skin's fast-forward button uses.
    static var fastForwardSpeed: Int {
        get { defaults.object(forKey: "settings.fastForwardSpeed") as? Int ?? 3 }
        set { defaults.set(newValue, forKey: "settings.fastForwardSpeed") }
    }

    /// Send an imported .zip/.rar/.7z to the trash, to free its space.
    static var deleteArchiveAfterImport: Bool {
        get { defaults.object(forKey: "settings.deleteArchive") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "settings.deleteArchive") }
    }

    /// The FPS / CPU / memory readout during games.
    static var showPerformance: Bool {
        get { defaults.object(forKey: "settings.showPerformance") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "settings.showPerformance") }
    }

    /// Pause when the app leaves the screen.
    static var pauseOnBackground: Bool {
        get { defaults.object(forKey: "settings.pauseOnBackground") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "settings.pauseOnBackground") }
    }
}
