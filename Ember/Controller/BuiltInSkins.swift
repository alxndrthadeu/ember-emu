import SwiftUI
import UIKit

/// The art styles Ember draws itself.
enum BuiltInStyle: String, Hashable {
    /// The default: an orange handheld, in Ember's palette.
    case ember
    /// Liquid Glass buttons over a dark controller area.
    case glass
}

/// Ember's own skins. Both share one layout, in Delta's point space,
/// so their hit areas work exactly like an imported skin's.
enum BuiltInSkins {
    static let ember = Skin(id: "ember.laranja", name: String(localized: "Ember Laranja"),
                            source: .builtIn(.ember), portrait: portrait, landscape: landscape)
    static let glass = Skin(id: "ember.vidro", name: String(localized: "Vidro"),
                            source: .builtIn(.glass), portrait: portrait, landscape: landscape)
    static let all = [ember, glass]
}
