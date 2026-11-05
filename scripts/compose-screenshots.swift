// Frames the raw App Store screenshots (scripts/store-screenshots.sh)
// in Ember's look: a headline in SF Pro Rounded, a background from the
// app's palette, the icon's pixel flame and a few pixel sparks, and
// the screenshot inside a drawn iPhone.
//
// (No Settings slide: its skins footer names other apps, which App
// Store metadata must not.)
//
// Usage: swift scripts/compose-screenshots.swift <raw dir> <out dir> [lang ...]
// Output: <out dir>/<lang>/NN-name.png, 1320×2868 (6.9" iPhone).

import AppKit

let width = 1320, height = 2868

struct Slide {
    let raw: String
    let name: String
    let background: [UInt32]   // top to bottom
    let ink: UInt32            // headline color
    let soft: UInt32           // subtitle color
    let tilt: CGFloat          // degrees
    let flame: Bool
    let text: [String: (String, String)]
}

let cream: UInt32 = 0xF4E9D8, night: UInt32 = 0x1E1814, ink: UInt32 = 0x2B211C

let slides: [Slide] = [
    Slide(raw: "1-game-title", name: "01-pocket", background: [0xC83A1E, 0xEE6A2A], ink: cream, soft: 0xFBE3C8,
          tilt: 0, flame: true, text: [
            "pt-BR": ("Seus RPGs clássicos no bolso", "Jogos de RPG Maker XP, VX e VX Ace no iPhone"),
            "en": ("Classic RPGs in your pocket", "RPG Maker XP, VX and VX Ace games on iPhone"),
            "es": ("Tus RPG clásicos en el bolsillo", "Juegos de RPG Maker XP, VX y VX Ace en el iPhone")]),
    Slide(raw: "2-game-talk", name: "02-controls", background: [0x2A221D, night], ink: cream, soft: 0xB9A794,
          tilt: -5, flame: false, text: [
            "pt-BR": ("Feito para jogar no toque", "Controle na tela, Bluetooth ou USB"),
            "en": ("Made for touch", "On-screen controls, Bluetooth or USB"),
            "es": ("Hecho para jugar al tacto", "Controles en pantalla, Bluetooth o USB")]),
    Slide(raw: "5-library", name: "03-library", background: [cream, 0xEADBC3], ink: ink, soft: 0x6E5B4E,
          tilt: 0, flame: false, text: [
            "pt-BR": ("Sua estante de aventuras", "Continue exatamente de onde parou"),
            "en": ("Your shelf of adventures", "Pick up right where you left off"),
            "es": ("Tu estantería de aventuras", "Sigue justo donde lo dejaste")]),
    Slide(raw: "3-ember-menu", name: "04-save", background: [0xF7B538, 0xEE6A2A], ink: ink, soft: 0x4A2A18,
          tilt: 5, flame: false, text: [
            "pt-BR": ("Salve quando quiser", "Save rápido, avanço até 5x e capturas"),
            "en": ("Save whenever you like", "Quick saves, up to 5x speed and screenshots"),
            "es": ("Guarda cuando quieras", "Guardado rápido, hasta 5x y capturas")]),
    Slide(raw: "6-import", name: "05-import", background: [0x2E8C83, 0x1D5E58], ink: cream, soft: 0xCFEDE9,
          tilt: 0, flame: false, text: [
            "pt-BR": ("Traga jogos do seu jeito", ".zip, .rar, .7z, pasta, Wi-Fi ou cabo"),
            "en": ("Bring games your way", ".zip, .rar, .7z, folders, Wi-Fi or cable"),
            "es": ("Trae juegos a tu manera", ".zip, .rar, .7z, carpeta, Wi-Fi o cable")]),
    Slide(raw: "4-game-menu", name: "06-play", background: [0x3A2F28, night], ink: cream, soft: 0xB9A794,
          tilt: -4, flame: false, text: [
            "pt-BR": ("Abre e joga", "O Ember escolhe a versão certa de cada jogo"),
            "en": ("Open and play", "Ember picks the right setup for each game"),
            "es": ("Abre y juega", "Ember elige la versión correcta de cada juego")]),
]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

// The app icon's flame (scripts/make-app-icon.py), light variant.
let flameMap = ["....1....", "...111...", "...1211..", "..12211..", "..122211.",
                ".1223221.", ".1233321.", ".1233321.", "..12321..", "...111..."]
let flameColors: [Character: UInt32] = ["1": 0xC83A1E, "2": 0xEE6A2A, "3": 0xF7B538]
let flameColorsOnRed: [Character: UInt32] = ["1": 0xF4E9D8, "2": 0xFBD38A, "3": 0xF7B538]

func drawFlame(at origin: CGPoint, cell: CGFloat, colors: [Character: UInt32], in ctx: CGContext) {
    for (row, line) in flameMap.enumerated() {
        for (col, ch) in line.enumerated() {
            guard let hex = colors[ch] else { continue }
            ctx.setFillColor(color(hex).cgColor)
            // y grows up in Core Graphics: row 0 is the flame's top.
            ctx.fill(CGRect(x: origin.x + CGFloat(col) * cell, y: origin.y - CGFloat(row + 1) * cell,
                            width: cell, height: cell))
        }
    }
}

func compose(_ slide: Slide, lang: String, rawDir: String, outDir: String) throws {
    guard let (title, subtitle) = slide.text[lang] else { return }
    let rawPath = "\(rawDir)/\(lang)/\(slide.raw).png"
    guard let shot = NSImage(contentsOfFile: rawPath),
          let shotCG = shot.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("missing \(rawPath)"); return
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext
    let W = CGFloat(width), H = CGFloat(height)

    // Background gradient, top to bottom.
    let colors = slide.background.map { color($0).cgColor } as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil)!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])

    // A warm glow behind the phone.
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [color(0xF7B538, 0.35).cgColor, color(0xF7B538, 0).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: W / 2, y: H * 0.45), startRadius: 0,
                           endCenter: CGPoint(x: W / 2, y: H * 0.45), endRadius: W * 0.75, options: [])

    // Pixel sparks, the same on every slide of a set.
    var seed: UInt64 = 7
    func next() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
    for i in 0..<18 {
        let size: CGFloat = [10, 14, 18][i % 3]
        let x = next() * W, y = H * 0.12 + next() * H * 0.8
        let edge = x < W * 0.12 || x > W * 0.88 || y < H * 0.25
        ctx.setFillColor(color(0xF7B538, edge ? 0.55 : 0.25).cgColor)
        ctx.fill(CGRect(x: (x / 4).rounded() * 4, y: (y / 4).rounded() * 4, width: size, height: size))
    }

    // Headline and subtitle.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineSpacing = -6
    var top = H - 170
    if slide.flame {
        let cell: CGFloat = 14
        drawFlame(at: CGPoint(x: W / 2 - cell * 4.5, y: top), cell: cell, colors: flameColorsOnRed, in: ctx)
        top -= cell * 10 + 34
    }
    let titleAttrs: [NSAttributedString.Key: Any] = [.font: rounded(112, .bold), .foregroundColor: color(slide.ink),
                                                     .paragraphStyle: paragraph, .kern: -1.5]
    let titleText = NSAttributedString(string: title, attributes: titleAttrs)
    let titleBox = titleText.boundingRect(with: NSSize(width: W - 160, height: 600),
                                          options: [.usesLineFragmentOrigin, .usesFontLeading])
    titleText.draw(with: NSRect(x: 80, y: top - titleBox.height, width: W - 160, height: titleBox.height),
                   options: [.usesLineFragmentOrigin, .usesFontLeading])
    top -= titleBox.height + 26
    let subAttrs: [NSAttributedString.Key: Any] = [.font: rounded(54, .medium), .foregroundColor: color(slide.soft),
                                                   .paragraphStyle: paragraph]
    let subText = NSAttributedString(string: subtitle, attributes: subAttrs)
    let subBox = subText.boundingRect(with: NSSize(width: W - 200, height: 400),
                                      options: [.usesLineFragmentOrigin, .usesFontLeading])
    subText.draw(with: NSRect(x: 100, y: top - subBox.height, width: W - 200, height: subBox.height),
                 options: [.usesLineFragmentOrigin, .usesFontLeading])
    top -= subBox.height

    // The phone: the screenshot inside a dark bezel, centered under the
    // text and running off the bottom edge.
    let scale: CGFloat = 0.78
    let screen = CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
    let bezel: CGFloat = 24
    let phone = CGSize(width: screen.width + bezel * 2, height: screen.height + bezel * 2)
    let phoneTop = top - 70
    let center = CGPoint(x: W / 2, y: phoneTop - phone.height / 2)

    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: slide.tilt * .pi / 180)
    let body = CGRect(x: -phone.width / 2, y: -phone.height / 2, width: phone.width, height: phone.height)
    // Shadow, then the frame.
    ctx.setShadow(offset: CGSize(width: 0, height: -30), blur: 80, color: color(0x000000, 0.35).cgColor)
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: 150, cornerHeight: 150, transform: nil))
    ctx.setFillColor(color(0x15100D).cgColor)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    // A thin warm rim, like the app's metal.
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 3, dy: 3), cornerWidth: 147, cornerHeight: 147, transform: nil))
    ctx.setStrokeColor(color(0x5A4A40).cgColor)
    ctx.setLineWidth(4)
    ctx.strokePath()
    // The screenshot, clipped to the screen's corners.
    let screenRect = body.insetBy(dx: bezel, dy: bezel)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screenRect, cornerWidth: 128, cornerHeight: 128, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(shotCG, in: screenRect)
    ctx.restoreGState()
    // The island.
    let island = CGRect(x: -150, y: screenRect.maxY - 36 - 98, width: 300, height: 98)
    ctx.addPath(CGPath(roundedRect: island, cornerWidth: 49, cornerHeight: 49, transform: nil))
    ctx.setFillColor(color(0x000000).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    try FileManager.default.createDirectory(atPath: "\(outDir)/\(lang)", withIntermediateDirectories: true)
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: URL(fileURLWithPath: "\(outDir)/\(lang)/\(slide.name).png"))
    print("  \(lang)/\(slide.name).png")
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: swift compose-screenshots.swift <raw dir> <out dir> [lang ...]")
    exit(1)
}
let langs = args.count > 3 ? Array(args[3...]) : ["pt-BR", "en", "es"]
for lang in langs {
    for slide in slides {
        try compose(slide, lang: lang, rawDir: args[1], outDir: args[2])
    }
}
