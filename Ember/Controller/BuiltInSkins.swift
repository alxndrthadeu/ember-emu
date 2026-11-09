import SwiftUI
import UIKit

/// The art styles Ember draws itself.
enum BuiltInStyle: String, Hashable {
    /// Translucent shells, see-through plastic with the board inside, in
    /// Ember's palette. `ember` (orange) is the default.
    case ember, brasa, musgo, fume
    /// Liquid Glass buttons over a dark controller area.
    case glass

    /// A translucent shell (every style but Vidro).
    var isShell: Bool { self != .glass }

    var palette: ShellPalette {
        switch self {
        case .ember, .glass:
            ShellPalette(light: Color(hex: 0xF8A45A), base: Color(hex: 0xEE6A2A), deep: Color(hex: 0xA8401A))
        case .brasa:
            ShellPalette(light: Color(hex: 0xE8603C), base: Color(hex: 0xC83A1E), deep: Color(hex: 0x7E2212))
        case .musgo:
            ShellPalette(light: Color(hex: 0x5CC2B6), base: Color(hex: 0x2E8C83), deep: Color(hex: 0x17544E))
        case .fume:
            ShellPalette(light: Color(hex: 0x5E5552), base: Color(hex: 0x3A3331), deep: Color(hex: 0x1B1716))
        }
    }
}

/// The colors of a translucent shell. Buttons are the same warm
/// charcoal on every color.
struct ShellPalette {
    let light: Color
    let base: Color
    let deep: Color

    var button: Color { Color(hex: 0x2C2426) }
    var buttonLight: Color { Color(hex: 0x4A3F42) }
    var label: Color { Color(hex: 0xF4E9D8).opacity(0.88) }
}

/// Ember's own skins. They share one layout, in Delta's point space,
/// so their hit areas work exactly like an imported skin's.
enum BuiltInSkins {
    static let ember = shell(.ember, id: "ember.laranja", name: String(localized: "Ember Laranja"))
    static let brasa = shell(.brasa, id: "ember.brasa", name: String(localized: "Ember Brasa"))
    static let musgo = shell(.musgo, id: "ember.musgo", name: String(localized: "Ember Musgo"))
    static let fume = shell(.fume, id: "ember.fume", name: String(localized: "Ember Fumê"))
    static let glass = Skin(id: "ember.vidro", name: String(localized: "Vidro"),
                            source: .builtIn(.glass), portrait: portrait, landscape: landscape)
    static let all = [ember, brasa, musgo, fume, glass]

    private static func shell(_ style: BuiltInStyle, id: String, name: String) -> Skin {
        Skin(id: id, name: name, source: .builtIn(style), portrait: portrait, landscape: landscape)
    }
}
