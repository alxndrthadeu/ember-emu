import Foundation
import UIKit

/// A controller skin: the artwork around the game and where each
/// button sits, for portrait and landscape.
///
/// Ember reads the Delta skin format (.deltaskin), which Manic EMU also
/// uses (.manicskin): a zip with an info.json and PDF or PNG artwork.
/// Spec: https://noah978.gitbook.io/delta-docs/skins
struct Skin: Identifiable, Hashable {
    enum Source: Hashable {
        /// Drawn by Ember (BuiltInSkins).
        case builtIn(BuiltInStyle)
        /// Unpacked under Application Support/Skins/<folder>.
        case imported(URL)
    }

    let id: String
    let name: String
    let source: Source
    let portrait: SkinLayout?
    let landscape: SkinLayout?
    /// The console the skin was drawn for (Delta's gameTypeIdentifier,
    /// e.g. com.rileytestut.delta.game.snes). Nil for built-in skins.
    var gameType: String? = nil

    /// The controller types this skin has the buttons for. Built-in
    /// skins draw every type.
    var covers: Set<ControllerType> {
        guard !isBuiltIn else { return Set(ControllerType.allCases) }
        let items = (portrait?.items ?? []) + (landscape?.items ?? [])
        let inputs = Set(items.flatMap(\.inputs))
        let directions = items.contains { $0.kind == .dpad || $0.kind == .stick }
        let stick = items.contains { $0.kind == .stick }
        var result = Set<ControllerType>()
        guard directions, inputs.contains(.key(.confirm)), inputs.contains(.key(.back)) else { return result }
        result.insert(.classic2)
        let fourButtons = inputs.contains(.key(.x)) && inputs.contains(.key(.y))
        if fourButtons { result.insert(.classic4) }
        if fourButtons && stick { result.insert(.modern) }
        return result
    }

    var isBuiltIn: Bool {
        if case .builtIn = source { return true }
        return false
    }

    func layout(portrait isPortrait: Bool) -> SkinLayout? {
        isPortrait ? portrait : landscape
    }

    // A skin is its identifier.
    static func == (lhs: Skin, rhs: Skin) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One orientation of a skin, in its own point space (`mappingSize`),
/// stretched to the screen at run time as Delta does.
struct SkinLayout: Equatable {
    var mappingSize: CGSize
    /// The artwork: a PDF (resizable) or a PNG. Nil for built-in skins.
    var artwork: URL?
    var items: [SkinItem]
    /// Where the game picture goes. Nil: Ember's default placement.
    var screen: CGRect?
    var extendedEdges: UIEdgeInsets
    /// The skin allows a see-through controller (landscape over the game).
    var translucent: Bool
    /// Where an iPhone Duo folds, in mapping points: y in portrait, x in
    /// landscape. Set only by the split layouts, which keep the game and
    /// the controls on their own half.
    var fold: CGFloat? = nil
    /// Where the artwork goes, in mapping points (nil: all of it). A
    /// Delta skin drawn for the bottom of the screen only is placed
    /// there, with the game above.
    var artworkFrame: CGRect? = nil
    /// A recomposed skin (SkinRecomposer): no single artwork, a
    /// background in the skin's own colors and each button drawn from
    /// its cut-out sprite.
    var backdrop: SkinBackdrop? = nil

    var hasMenuButton: Bool {
        items.contains { $0.inputs.contains(.menu) }
    }

    var hasKeyboardButton: Bool {
        items.contains { $0.inputs.contains(.keyboard) }
    }

    var menuFrame: CGRect? {
        items.first { $0.inputs.contains(.menu) }?.frame
    }
}

struct SkinItem: Equatable {
    enum Kind: Hashable {
        case button
        /// Split into directions by where the finger is.
        case dpad
        /// An analog stick: eight directions from where the thumb drags
        /// the knob (inputs: up, down, left, right).
        case stick
    }

    var kind: Kind
    /// For a button: what it presses. For a d-pad: up, down, left,
    /// right in that order.
    var inputs: [SkinInput]
    var frame: CGRect
    /// Overrides the layout's extendedEdges when set.
    var extendedEdges: UIEdgeInsets?
    /// The button's own picture, drawn in its frame: an asset of the
    /// skin (Delta's item "asset") or a piece cut out of its artwork.
    var sprite: URL? = nil
    /// A stick's knob picture (Delta's "thumbstick"), and its size in
    /// mapping points.
    var thumb: URL? = nil
    var thumbSize: CGSize? = nil
}

/// The look of a recomposed skin around its buttons.
struct SkinBackdrop: Equatable {
    var top: UIColor
    var bottom: UIColor
    /// The frame around the game picture.
    var bezel: UIColor
}

/// What a skin button does in Ember.
enum SkinInput: Hashable {
    case key(GameKey)
    /// Ember's in-game menu.
    case menu
    /// Opens the system keyboard, for games that poll a PC keyboard.
    /// Shown for every game (ControlsOverlay).
    case keyboard
    /// iPhone Duo DS layout: moves the game to the other screen.
    case swapScreens
    /// Fast forward while held.
    case fastForward
    /// Fast forward on until pressed again.
    case toggleFastForward
    /// An input Ember has no use for (quickSave, x, y...): ignored.
    case unsupported(String)

    init(deltaName name: String) {
        switch name.lowercased() {
        case "a": self = .key(.confirm)
        case "b": self = .key(.back)
        case "start": self = .key(.start)
        case "select": self = .key(.select)
        case "l": self = .key(.l)
        case "r": self = .key(.r)
        case "x": self = .key(.x)
        case "y": self = .key(.y)
        case "l2", "zl": self = .key(.l2)
        case "r2", "zr": self = .key(.r2)
        // Nintendo 64: C buttons and Z become the modern controller's
        // extra buttons.
        case "cup": self = .key(.x)
        case "cleft": self = .key(.y)
        case "z": self = .key(.l2)
        case "cright": self = .key(.r2)
        // PlayStation (Manic EMU): cross and circle confirm and cancel.
        case "cross": self = .key(.confirm)
        case "circle": self = .key(.back)
        case "square": self = .key(.y)
        case "triangle": self = .key(.x)
        case "l1": self = .key(.l)
        case "r1": self = .key(.r)
        case "up": self = .key(.up)
        case "down": self = .key(.down)
        case "left": self = .key(.left)
        case "right": self = .key(.right)
        case "menu": self = .menu
        case "keyboard": self = .keyboard
        case "fastforward": self = .fastForward
        case "togglefastforward": self = .toggleFastForward
        default: self = .unsupported(name)
        }
    }
}

// MARK: - Reading a .deltaskin

enum SkinParser {
    enum ParseError: LocalizedError {
        case noInfo
        case noIPhoneLayout(String)

        var errorDescription: String? {
            switch self {
            case .noInfo:
                String(localized: "Este arquivo não é uma skin: falta o info.json.")
            case .noIPhoneLayout(let name):
                String(localized: "A skin “\(name)” não tem layout para iPhone.")
            }
        }
    }

    /// Reads an unpacked skin folder.
    static func parse(folder: URL) throws -> Skin {
        let infoURL = folder.appendingPathComponent("info.json")
        guard let data = try? Data(contentsOf: infoURL),
              let info = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ParseError.noInfo }

        let name = info["name"] as? String ?? folder.lastPathComponent
        let identifier = info["identifier"] as? String ?? folder.lastPathComponent
        let representations = info["representations"] as? [String: Any] ?? [:]
        guard let iphone = value(representations, "iphone") as? [String: Any] else {
            throw ParseError.noIPhoneLayout(name)
        }
        // Notched iPhones use edgeToEdge; older skins only have standard.
        let variant = (value(iphone, "edgeToEdge") ?? value(iphone, "standard")) as? [String: Any] ?? [:]
        let portrait = (variant["portrait"] as? [String: Any]).flatMap { layout($0, in: folder) }
        let landscape = (variant["landscape"] as? [String: Any]).flatMap { layout($0, in: folder) }
        guard portrait != nil || landscape != nil else { throw ParseError.noIPhoneLayout(name) }

        return Skin(id: identifier, name: name, source: .imported(folder),
                    portrait: portrait, landscape: landscape,
                    gameType: info["gameTypeIdentifier"] as? String)
    }

    private static func layout(_ json: [String: Any], in folder: URL) -> SkinLayout? {
        guard let mapping = size(json["mappingSize"]) else { return nil }

        var artwork: URL?
        if let assets = json["assets"] as? [String: Any] {
            let name = (assets["resizable"] ?? assets["large"] ?? assets["medium"] ?? assets["small"]) as? String
            artwork = name.map { folder.appendingPathComponent($0) }
        }

        let items = (json["items"] as? [[String: Any]] ?? []).compactMap { item($0, in: folder) }

        var screen: CGRect?
        if let screens = json["screens"] as? [[String: Any]], let first = screens.first {
            screen = rect(first["outputFrame"])
        } else {
            screen = rect(json["gameScreenFrame"])
        }

        return SkinLayout(mappingSize: mapping, artwork: artwork, items: items, screen: screen,
                          extendedEdges: edges(json["extendedEdges"]) ?? .zero,
                          translucent: json["translucent"] as? Bool ?? false)
    }

    private static func item(_ json: [String: Any], in folder: URL) -> SkinItem? {
        guard let frame = rect(json["frame"]) else { return nil }
        let extended = edges(json["extendedEdges"])
        // Newer skins draw some buttons as separate pictures.
        let sprite = ((json["asset"] as? [String: Any])?["name"] as? String).map { folder.appendingPathComponent($0) }
        if let list = json["inputs"] as? [String] {
            return SkinItem(kind: .button, inputs: list.map(SkinInput.init(deltaName:)),
                            frame: frame, extendedEdges: extended, sprite: sprite)
        }
        if let map = json["inputs"] as? [String: String],
           let up = map["up"], let down = map["down"], let left = map["left"], let right = map["right"] {
            // A thumbstick's analogStick* names read as directions too.
            let analog = up.hasPrefix("analogStick") || json["thumbstick"] != nil
            let names = [up, down, left, right].map { name -> String in
                name.hasPrefix("analogStick") ? String(name.dropFirst("analogStick".count)) : name
            }
            var item = SkinItem(kind: analog ? .stick : .dpad, inputs: names.map(SkinInput.init(deltaName:)),
                                frame: frame, extendedEdges: extended, sprite: sprite)
            if let thumb = json["thumbstick"] as? [String: Any], let file = thumb["name"] as? String {
                item.thumb = folder.appendingPathComponent(file)
                item.thumbSize = size(thumb)
            }
            return item
        }
        return nil
    }

    /// Dictionary lookup that ignores case ("iPhone" in old skins).
    private static func value(_ dictionary: [String: Any], _ key: String) -> Any? {
        dictionary.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    private static func number(_ any: Any?) -> CGFloat? {
        (any as? NSNumber).map { CGFloat(truncating: $0) }
    }

    private static func size(_ any: Any?) -> CGSize? {
        guard let json = any as? [String: Any],
              let width = number(json["width"]), let height = number(json["height"]),
              width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func rect(_ any: Any?) -> CGRect? {
        guard let json = any as? [String: Any],
              let x = number(json["x"]), let y = number(json["y"]),
              let width = number(json["width"]), let height = number(json["height"])
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func edges(_ any: Any?) -> UIEdgeInsets? {
        guard let json = any as? [String: Any] else { return nil }
        return UIEdgeInsets(top: number(json["top"]) ?? 0, left: number(json["left"]) ?? 0,
                            bottom: number(json["bottom"]) ?? 0, right: number(json["right"]) ?? 0)
    }
}

// MARK: - Artwork

/// Renders a skin's PDF or PNG artwork at a given size, cached.
enum SkinArtwork {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(_ url: URL, size: CGSize) -> UIImage? {
        let key = "\(url.path)|\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let image: UIImage?
        if url.pathExtension.lowercased() == "pdf" {
            image = renderPDF(url, size: size)
        } else {
            image = UIImage(contentsOfFile: url.path)
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    private static func renderPDF(_ url: URL, size: CGSize) -> UIImage? {
        guard size.width > 0, size.height > 0,
              let document = CGPDFDocument(url as CFURL),
              let page = document.page(at: 1)
        else { return nil }
        let box = page.getBoxRect(.mediaBox)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cg = context.cgContext
            // PDF space is bottom-up; the skin stretches to fill, as in Delta.
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: size.width / box.width, y: -size.height / box.height)
            cg.translateBy(x: -box.minX, y: -box.minY)
            cg.drawPDFPage(page)
        }
    }
}
