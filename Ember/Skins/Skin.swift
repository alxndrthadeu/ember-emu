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
    }

    var kind: Kind
    /// For a button: what it presses. For a d-pad: up, down, left,
    /// right in that order.
    var inputs: [SkinInput]
    var frame: CGRect
    /// Overrides the layout's extendedEdges when set.
    var extendedEdges: UIEdgeInsets?
}

/// What a skin button does in Ember.
enum SkinInput: Hashable {
    case key(GameKey)
    /// Ember's in-game menu.
    case menu
    /// Opens the system keyboard, for games that poll a PC keyboard.
    /// Shown only for those games (GameEntry.wantsKeyboardButton).
    case keyboard
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
                    portrait: portrait, landscape: landscape)
    }

    private static func layout(_ json: [String: Any], in folder: URL) -> SkinLayout? {
        guard let mapping = size(json["mappingSize"]) else { return nil }

        var artwork: URL?
        if let assets = json["assets"] as? [String: Any] {
            let name = (assets["resizable"] ?? assets["large"] ?? assets["medium"] ?? assets["small"]) as? String
            artwork = name.map { folder.appendingPathComponent($0) }
        }

        let items = (json["items"] as? [[String: Any]] ?? []).compactMap(item)

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

    private static func item(_ json: [String: Any]) -> SkinItem? {
        guard let frame = rect(json["frame"]) else { return nil }
        let extended = edges(json["extendedEdges"])
        if let list = json["inputs"] as? [String] {
            return SkinItem(kind: .button, inputs: list.map(SkinInput.init(deltaName:)),
                            frame: frame, extendedEdges: extended)
        }
        if let map = json["inputs"] as? [String: String],
           let up = map["up"], let down = map["down"], let left = map["left"], let right = map["right"] {
            // A thumbstick's analogStick* names read as directions too.
            let names = [up, down, left, right].map { name -> String in
                name.hasPrefix("analogStick") ? String(name.dropFirst("analogStick".count)) : name
            }
            return SkinItem(kind: .dpad, inputs: names.map(SkinInput.init(deltaName:)),
                            frame: frame, extendedEdges: extended)
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
