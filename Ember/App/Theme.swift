import SwiftUI
import UIKit

/// The Ember identity (CLAUDE.md): the warm "Lanterna" palette on a
/// modern Liquid Glass interface. Pixel art lives only in the app icon.
/// Every color the app uses comes from here.
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
    static let controlLabel = Color(hex: 0xF4E9D8).opacity(0.9)
    /// Glass over the dark controller area, warmed with the cream.
    static let controlGlass = EmberGlass.regular.tint(Color(hex: 0xF4E9D8).opacity(0.08))
    static let controlGlassPressed = EmberGlass.regular.tint(Color(hex: 0xF4E9D8).opacity(0.30))

    // MARK: Shapes

    static let cardRadius: CGFloat = 22

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
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

/// The Ember flame inside the app: the system symbol, brasa to âmbar.
struct EmberFlame: View {
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(
                LinearGradient(colors: [Theme.highlight, Color(hex: 0xEE6A2A), Color(hex: 0xC83A1E)],
                               startPoint: .bottom, endPoint: .top))
            .accessibilityHidden(true)
    }
}
