import Foundation
import UIKit

/// A Delta or Manic skin taken apart into Ember's own pieces: each
/// button's picture, the stick's knob, and the colors of the shell.
/// With these, SkinRecomposer draws the skin on any device and layout
/// Ember has (an open iPhone Duo, a phone orientation the skin lacks)
/// with the artist's own buttons.
///
/// Stored next to the skin as `Converted.ember/` (ember.json and PNGs).
/// Made on the device from skins the player imported; Ember never
/// ships or shares them.
struct EmberSkinPackage: Codable, Equatable {
    struct Part: Codable, Equatable {
        /// PNG in the package folder.
        var file: String
        /// Width / height of the picture.
        var aspect: CGFloat
    }

    struct RGB: Codable, Equatable {
        var r: CGFloat, g: CGFloat, b: CGFloat
        var color: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
    }

    var format = EmberSkinConverter.format
    var sourceID: String
    var gameType: String?
    /// Part by key: "dpad", "stick", "a", "b", "x", "y", "l", "r", "l2",
    /// "r2", "start", "select", "menu".
    var parts: [String: Part]
    /// The stick's knob, when the skin draws it apart.
    var thumb: Part?
    var top: RGB
    var bottom: RGB

    /// The folder this package lives in (set when loaded).
    var folder: URL?

    enum CodingKeys: String, CodingKey {
        case format, sourceID, gameType, parts, thumb, top, bottom
    }

    var backdrop: SkinBackdrop {
        let bottomColor = bottom.color
        return SkinBackdrop(top: top.color, bottom: bottomColor, bezel: Self.darker(bottomColor, by: 0.72))
    }

    func url(_ part: Part) -> URL? { folder?.appendingPathComponent(part.file) }

    /// The part for one of a layout's items.
    func part(for item: SkinItem) -> Part? {
        guard let key = EmberSkinConverter.key(for: item) else { return nil }
        if item.kind == .stick { return parts["stick"] ?? parts["dpad"] }
        if item.kind == .dpad { return parts["dpad"] ?? parts["stick"] }
        return parts[key]
    }

    static func darker(_ color: UIColor, by amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * (1 - amount), green: g * (1 - amount), blue: b * (1 - amount), alpha: 1)
    }
}

enum EmberSkinConverter {
    static let folderName = "Converted.ember"
    /// Bumped when conversion changes: older packages are made again.
    static let format = 3
    private static let scale: CGFloat = 3
    /// Guarded by `lock`.
    nonisolated(unsafe) private static var cache: [String: EmberSkinPackage] = [:]
    private static let lock = NSLock()

    /// The key of an item's part.
    static func key(for item: SkinItem) -> String? {
        switch item.kind {
        case .dpad: return "dpad"
        case .stick: return "stick"
        case .button:
            switch item.inputs.first {
            case .key(.confirm): return "a"
            case .key(.back): return "b"
            case .key(.x): return "x"
            case .key(.y): return "y"
            case .key(.l): return "l"
            case .key(.r): return "r"
            case .key(.l2): return "l2"
            case .key(.r2): return "r2"
            case .key(.start): return "start"
            case .key(.select): return "select"
            case .menu: return "menu"
            default: return nil
            }
        }
    }

    /// The package of an imported skin: read from disk, or made now.
    static func package(for skin: Skin) -> EmberSkinPackage? {
        guard case .imported(let folder) = skin.source else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[skin.id] { return cached }
        let target = folder.appendingPathComponent(folderName, isDirectory: true)
        if var saved = load(target), saved.sourceID == skin.id, saved.format == format {
            saved.folder = target
            cache[skin.id] = saved
            return saved
        }
        guard var made = try? convert(skin, into: target) else { return nil }
        made.folder = target
        cache[skin.id] = made
        return made
    }

    static func forget(_ skin: Skin) {
        lock.lock()
        cache[skin.id] = nil
        lock.unlock()
    }

    private static func load(_ folder: URL) -> EmberSkinPackage? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("ember.json")) else { return nil }
        return try? JSONDecoder().decode(EmberSkinPackage.self, from: data)
    }

    /// Cuts the skin into parts and writes the package.
    static func convert(_ skin: Skin, into target: URL) throws -> EmberSkinPackage {
        let fm = FileManager.default
        try? fm.removeItem(at: target)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)

        // Portrait first: phone skins draw their controls best there.
        guard let layout = skin.portrait ?? skin.landscape else { throw CocoaError(.fileReadCorruptFile) }
        let pixelSize = CGSize(width: layout.mappingSize.width * scale, height: layout.mappingSize.height * scale)
        let art = layout.artwork.flatMap { render($0, size: pixelSize) }

        // The shell's colors, from the art's left edge (usually clear of
        // buttons), near its top and its bottom.
        let (top, bottom) = art.map(edgeColors) ?? (UIColor(white: 0.2, alpha: 1), UIColor(white: 0.12, alpha: 1))

        var parts: [String: EmberSkinPackage.Part] = [:]
        var thumb: EmberSkinPackage.Part?
        for item in layout.items {
            guard let key = key(for: item), parts[key] == nil else { continue }
            let size = CGSize(width: item.frame.width * scale, height: item.frame.height * scale)
            let image: UIImage?
            if let sprite = item.sprite {
                image = render(sprite, size: size)
            } else if let art {
                // Cut from the artwork: the shell around the button goes.
                var piece = crop(art, item.frame.applying(.init(scaleX: scale, y: scale)))
                    .flatMap { removingBackground($0, shell: [top, bottom]) }
                // Round pieces (sticks, round buttons) keep only their circle:
                // the frame often cuts into the art around them.
                let square = abs(item.frame.width - item.frame.height) < min(item.frame.width, item.frame.height) * 0.15
                if item.kind == .stick || (item.kind == .button && square) {
                    piece = piece.map(circled)
                }
                image = piece
            } else {
                image = nil
            }
            if let image, let data = image.pngData() {
                let file = "\(key).png"
                try data.write(to: target.appendingPathComponent(file))
                parts[key] = .init(file: file, aspect: item.frame.width / max(item.frame.height, 1))
            }
            if let knob = item.thumb, let knobSize = item.thumbSize,
               let image = render(knob, size: CGSize(width: knobSize.width * scale, height: knobSize.height * scale)),
               let data = image.pngData() {
                try data.write(to: target.appendingPathComponent("thumb.png"))
                thumb = .init(file: "thumb.png", aspect: knobSize.width / max(knobSize.height, 1))
            }
        }

        func rgb(_ color: UIColor) -> EmberSkinPackage.RGB {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return .init(r: r, g: g, b: b)
        }
        let package = EmberSkinPackage(sourceID: skin.id, gameType: skin.gameType, parts: parts, thumb: thumb,
                                       top: rgb(top), bottom: rgb(bottom))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(package).write(to: target.appendingPathComponent("ember.json"))
        return package
    }

    // MARK: Pictures

    private static func render(_ url: URL, size: CGSize) -> UIImage? {
        guard size.width >= 1, size.height >= 1 else { return nil }
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
            let box = page.getBoxRect(.mediaBox)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                let cg = context.cgContext
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: size.width / box.width, y: -size.height / box.height)
                cg.translateBy(x: -box.minX, y: -box.minY)
                cg.drawPDFPage(page)
            }
        }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func crop(_ image: UIImage, _ rect: CGRect) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let area = rect.integral.intersection(bounds)
        guard !area.isEmpty, let piece = cg.cropping(to: area) else { return nil }
        return UIImage(cgImage: piece)
    }

    /// Clears the shell around a button cut from the artwork: a flood
    /// fill from the picture's edges through pixels that change little
    /// from their neighbor, stopping at the button's outline.
    static func removingBackground(_ image: UIImage, shell skinColors: [UIColor]) -> UIImage? {
        guard let cg = image.cgImage else { return image }
        let width = cg.width, height = cg.height
        guard width > 4, height > 4 else { return image }
        // The context owns its memory; `pixels` points into it.
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let raw = context.data
        else { return image }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = raw.bindMemory(to: UInt8.self, capacity: width * height * 4)

        func color(_ i: Int) -> (Int, Int, Int) {
            (Int(pixels[i * 4]), Int(pixels[i * 4 + 1]), Int(pixels[i * 4 + 2]))
        }
        func close(_ a: (Int, Int, Int), _ b: (Int, Int, Int), _ limit: Int) -> Bool {
            abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) <= limit
        }
        // The shell's color: the most common of the edge pixels' colors.
        var edge: [Int] = []
        for x in 0..<width { edge.append(x); edge.append((height - 1) * width + x) }
        for y in 0..<height { edge.append(y * width); edge.append(y * width + width - 1) }
        var counts: [Int: Int] = [:]
        for i in edge {
            let c = color(i)
            counts[(c.0 / 16) << 8 | (c.1 / 16) << 4 | (c.2 / 16), default: 0] += 1
        }
        guard let common = counts.max(by: { $0.value < $1.value })?.key else { return image }
        let shell = (((common >> 8) & 15) * 16 + 8, ((common >> 4) & 15) * 16 + 8, (common & 15) * 16 + 8)
        // Only when the edges are the skin's own shell color: a button that
        // fills its frame (a black shoulder) must not be cleared away.
        let matchesSkin = skinColors.contains { color in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return close(shell, (Int(r * 255), Int(g * 255), Int(b * 255)), 110)
        }
        guard matchesSkin else { return image }

        var cleared = [Bool](repeating: false, count: width * height)
        var queue: [Int] = edge.filter { close(color($0), shell, 90) }
        for i in queue { cleared[i] = true }
        var head = 0
        while head < queue.count {
            let i = queue[head]; head += 1
            let x = i % width, y = i / width
            let here = color(i)
            for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)] {
                guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                let n = ny * width + nx
                guard !cleared[n] else { continue }
                let c = color(n)
                if close(c, here, 30) && close(c, shell, 120) {
                    cleared[n] = true
                    queue.append(n)
                }
            }
        }
        // Nothing to clear, or the whole piece looked like shell: keep it.
        let total = cleared.filter { $0 }.count
        guard total > 0, total < width * height * 9 / 10 else { return image }
        for i in 0..<(width * height) where cleared[i] {
            pixels[i * 4] = 0; pixels[i * 4 + 1] = 0; pixels[i * 4 + 2] = 0; pixels[i * 4 + 3] = 0
        }
        guard let out = context.makeImage() else { return image }
        return UIImage(cgImage: out)
    }

    /// The picture inside its inscribed circle.
    static func circled(_ image: UIImage) -> UIImage {
        let size = image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let side = min(size.width, size.height)
            UIBezierPath(ovalIn: CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2,
                                        width: side, height: side)).addClip()
            image.draw(at: .zero)
        }
    }

    /// Average colors of a thin strip at the left edge, near the top and
    /// near the bottom of the art.
    private static func edgeColors(_ image: UIImage) -> (UIColor, UIColor) {
        guard let cg = image.cgImage else { return (.darkGray, .black) }
        let width = 8, height = 64
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let raw = context.data else { return (.darkGray, .black) }
        // Only the leftmost 6% of the art, squeezed into 8 columns.
        let strip = cg.cropping(to: CGRect(x: 0, y: 0, width: max(Int(Double(cg.width) * 0.06), 1), height: cg.height)) ?? cg
        context.interpolationQuality = .medium
        context.draw(strip, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = raw.bindMemory(to: UInt8.self, capacity: width * height * 4)
        func average(rows: Range<Int>) -> UIColor {
            var r = 0.0, g = 0.0, b = 0.0, n = 0.0
            for row in rows {
                for x in 1..<width {
                    let i = (row * width + x) * 4
                    let a = Double(pixels[i + 3])
                    guard a > 200 else { continue }
                    r += Double(pixels[i]); g += Double(pixels[i + 1]); b += Double(pixels[i + 2]); n += 1
                }
            }
            guard n > 0 else { return UIColor(white: 0.15, alpha: 1) }
            return UIColor(red: r / n / 255, green: g / n / 255, blue: b / n / 255, alpha: 1)
        }
        // CGContext rows go bottom-up in memory order of this buffer: row 0 is the top.
        return (average(rows: 3..<9), average(rows: 55..<61))
    }
}
