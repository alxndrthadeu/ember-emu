import SwiftUI
import UIKit

/// The "Lanterna" identity (CLAUDE.md): warm pixel art on cream, the
/// feel of a cartridge manual. Every color and font the app uses comes
/// from here.
enum Theme {
    // MARK: Palette (light / dark)

    static let background = dynamic(light: 0xF4E9D8, dark: 0x1E1814)
    static let surface = dynamic(light: 0xFBF5EA, dark: 0x2A221D)
    static let surface2 = dynamic(light: 0xEADBC3, dark: 0x3A2F28)
    static let primaryText = dynamic(light: 0x2B211C, dark: 0xF4E9D8)
    static let secondaryText = dynamic(light: 0x6E5B4E, dark: 0xB9A794)
    /// Brasa: the main action, selection. One per screen.
    static let accent = dynamic(light: 0xC83A1E, dark: 0xEE6A2A)
    /// Text on `accent`.
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x1E1814)
    /// Âmbar: something happening now (speed on, "Continuar", news).
    static let highlight = Color(hex: 0xF7B538)
    /// Text on `highlight`.
    static let onHighlight = Color(hex: 0x2B211C)
    /// Musgo: the only cool color, for on / done states.
    static let active = dynamic(light: 0x2E8C83, dark: 0x4DB3A8)

    // MARK: Game screen (dark in both modes)

    static let controllerBackground = Color(hex: 0x17120F)
    static let controlFill = Color(hex: 0xF4E9D8).opacity(0.10)
    static let controlFillPressed = Color(hex: 0xF4E9D8).opacity(0.28)
    static let controlStroke = Color(hex: 0xF4E9D8).opacity(0.22)
    static let controlLabel = Color(hex: 0xF4E9D8).opacity(0.88)

    // MARK: Shapes

    static let cardRadius: CGFloat = 18

    // MARK: Type

    /// Pixelify Sans: the logotype and big titles only, never body text.
    /// Use through `.pixelFont(_:)`, which also clears the rounded
    /// design the app sets at the root.
    static func pixel(_ size: CGFloat) -> Font {
        .custom(pixelFamily, size: size)
    }

    static func pixelUIFont(_ size: CGFloat) -> UIFont {
        UIFont(name: pixelFamily, size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }

    private static let pixelFamily = "Pixelify Sans"

    /// Large navigation titles in Pixelify, inline ones in SF Rounded.
    static func styleNavigationBars() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(background)
        appearance.largeTitleTextAttributes = [
            .font: pixelUIFont(36),
            .foregroundColor: UIColor(primaryText),
        ]
        let rounded = UIFont.systemFont(ofSize: 17, weight: .semibold)
        appearance.titleTextAttributes = [
            .font: UIFont(descriptor: rounded.fontDescriptor.withDesign(.rounded) ?? rounded.fontDescriptor,
                          size: 17),
            .foregroundColor: UIColor(primaryText),
        ]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension View {
    /// Pixelify Sans at this size. The app applies
    /// `.fontDesign(.rounded)` at the root, and SwiftUI then swaps any
    /// custom font for the rounded system font; this clears it again.
    func pixelFont(_ size: CGFloat) -> some View {
        font(Theme.pixel(size)).fontDesign(nil)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

/// The Ember flame, drawn from the same 9x10 map as the app icon.
struct PixelFlame: View {
    var cell: CGFloat = 8

    private static let map = [
        "....1....",
        "...111...",
        "...1211..",
        "..12211..",
        "..122211.",
        ".1223221.",
        ".1233321.",
        ".1233321.",
        "..12321..",
        "...111...",
    ]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, _ in
            for (y, row) in Self.map.enumerated() {
                for (x, character) in row.enumerated() {
                    guard let color = color(for: character) else { continue }
                    let rect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell,
                                      width: cell, height: cell)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: cell * 9, height: cell * 10)
        .accessibilityHidden(true)
    }

    private func color(for character: Character) -> Color? {
        let dark = scheme == .dark
        switch character {
        case "1": return Color(hex: dark ? 0xEE6A2A : 0xC83A1E)
        case "2": return Color(hex: dark ? 0xF48A3A : 0xEE6A2A)
        case "3": return Color(hex: 0xF7B538)
        default: return nil
        }
    }
}
