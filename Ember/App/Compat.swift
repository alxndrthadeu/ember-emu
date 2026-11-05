import SwiftUI

// iOS 17–25 support, as one big `if`.
//
// On iOS 26 and later every helper here calls the system's Liquid Glass
// with the same values the app used before: nothing changes there.
// Below iOS 26 Liquid Glass does not exist, so the same shapes get the
// system's translucent material instead, with the same tints.

enum EmberCompat {
    /// Development aid: EMBER_LEGACY_UI=1 takes the iOS 17–25 path on a
    /// newer system, to look at it in today's simulator (Xcode 27 no
    /// longer downloads iOS 17 or 18 simulators). Always false in
    /// release builds.
    #if DEBUG
    static let forceLegacy = ProcessInfo.processInfo.environment["EMBER_LEGACY_UI"] != nil
    #else
    static let forceLegacy = false
    #endif
}

/// A glass look, written like SwiftUI's `Glass` (`.regular`,
/// `.tint(_:)`, `.interactive()`), but compiling on iOS 17.
struct EmberGlass {
    var tint: Color?
    var isInteractive = false

    static let regular = EmberGlass()

    func tint(_ color: Color?) -> EmberGlass {
        var copy = self
        copy.tint = color
        return copy
    }

    func interactive(_ on: Bool = true) -> EmberGlass {
        var copy = self
        copy.isInteractive = on
        return copy
    }

    /// The system glass this stands for (iOS 26+).
    @available(iOS 26, *)
    var system: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if isInteractive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    /// `.glassEffect(_:in:)` on iOS 26+; a material in the same shape below.
    @ViewBuilder
    func emberGlass(_ glass: EmberGlass = .regular, in shape: some Shape) -> some View {
        if #available(iOS 26, *), !EmberCompat.forceLegacy {
            self.glassEffect(glass.system, in: shape)
        } else {
            self.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint = glass.tint {
                        shape.fill(tint)
                    }
                    shape.stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                }
            }
        }
    }

    /// `.buttonStyle(.glassProminent)` on iOS 26+; a filled button below.
    @ViewBuilder
    func emberGlassProminentButton() -> some View {
        if #available(iOS 26, *), !EmberCompat.forceLegacy {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// `.buttonStyle(.glass)` on iOS 26+; a tinted button below.
    @ViewBuilder
    func emberGlassButton() -> some View {
        if #available(iOS 26, *), !EmberCompat.forceLegacy {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// `GlassEffectContainer` on iOS 26+ (glass shapes blend and morph
/// together); a plain container below.
struct EmberGlassContainer<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26, *), !EmberCompat.forceLegacy {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
