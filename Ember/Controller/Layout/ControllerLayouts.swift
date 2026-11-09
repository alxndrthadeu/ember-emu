import SwiftUI
import UIKit

/// Everything that decides how a controller looks on one screen. The
/// game screen and the previews (Como você quer jogar?) build one and
/// ask `ControllerLayouts` for the layout, so both always match.
struct ControllerContext: Equatable {
    enum Device: Equatable {
        /// A regular iPhone (portrait height/width around 2.17).
        case phone
        /// An open iPhone Duo: `viewAspect` is long side / short side of
        /// the screen (about 1.46); half folded or flat.
        case duo(viewAspect: CGFloat, partiallyOpen: Bool)
    }

    var device: Device
    var portrait: Bool
    var type: ControllerType
    /// The game wants the keyboard button next to the gear.
    var keyboard = true
    /// Width / height of the game picture (nil: 4:3 until known).
    var gameAspect: CGFloat?
    /// Ajustes: Tela cheia (true) or Clássica, on phones in portrait.
    var fullWidth = true
    /// Ajustes: the Duo splits game and controller (true) or not.
    var duoSplit = true
    /// The Duo's DS layout with the game on the bottom window.
    var duoGameBelow = false

    /// The device a screen of this size is.
    static func device(for size: CGSize, partiallyOpen: Bool = false) -> Device {
        let long = max(size.width, size.height), short = max(min(size.width, size.height), 1)
        let aspect = (long / short * 100).rounded() / 100
        return aspect < ControllerLayouts.wideBelow ? .duo(viewAspect: aspect, partiallyOpen: partiallyOpen) : .phone
    }

    /// The context of the game screen now: the game's view size (or the
    /// whole screen outside a game) and the player's settings.
    @MainActor
    static func current(portrait: Bool, keyboard: Bool, type: ControllerType) -> ControllerContext {
        let skins = SkinStore.shared
        let layout = GameLayout.shared
        let device: Device
        if let aspect = layout.viewAspect {
            device = aspect < ControllerLayouts.wideBelow
                ? .duo(viewAspect: aspect, partiallyOpen: layout.hingePartiallyOpen) : .phone
        } else {
            device = Self.device(for: UIScreen.main.bounds.size, partiallyOpen: layout.hingePartiallyOpen)
        }
        return ControllerContext(device: device, portrait: portrait, type: type, keyboard: keyboard,
                                 gameAspect: layout.aspect, fullWidth: skins.portraitFullWidth,
                                 duoSplit: skins.duoSplit, duoGameBelow: skins.duoGameBelow)
    }
}

/// Builds the controller layout for a skin in a context.
///
/// Built-in skins (Ember Laranja, Vidro) start from the phone layouts
/// (PhoneLayouts.swift), are redrawn for the device (DuoLayouts.swift)
/// and get the buttons of their controller type (TypedLayouts.swift).
/// Imported skins (Delta, Manic) are used as drawn.
enum ControllerLayouts {
    /// Height / width below which a screen counts as wide (an open
    /// iPhone Duo is about 1.46; phones are about 2.17).
    static let wideBelow: CGFloat = 1.75

    /// The skin to draw: the chosen one, unless it lacks buttons the
    /// controller type needs (an imported GBA skin for a 4-button game);
    /// then Ember Laranja, which draws every type.
    static func effectiveSkin(_ chosen: Skin, type: ControllerType) -> Skin {
        guard type != .classic2, !chosen.isBuiltIn else { return chosen }
        let inputs = Set((chosen.portrait?.items ?? []).flatMap(\.inputs))
        switch type {
        case .classic2: return chosen
        case .classic4: return [SkinInput.key(.x), .key(.y)].allSatisfy(inputs.contains) ? chosen : BuiltInSkins.ember
        // Imported skins have no stick.
        case .modern: return BuiltInSkins.ember
        }
    }

    static func layout(for skin: Skin, in context: ControllerContext) -> SkinLayout {
        let own = skin.layout(portrait: context.portrait)
        guard own == nil || skin.isBuiltIn else { return own! }
        let phone = own ?? BuiltInSkins.ember.layout(portrait: context.portrait)!
        return BuiltInSkins.typed(builtIn(phone, in: context), type: context.type)
    }

    /// A built-in phone layout, adapted to the game and the device.
    private static func builtIn(_ phone: SkinLayout, in context: ControllerContext) -> SkinLayout {
        var adapted = BuiltInSkins.adapted(phone, keyboard: context.keyboard)
        if case .duo(let viewAspect, let partial) = context.device {
            // Split (the default): game on one half, controller on the
            // other, nothing on the crease. Lying flat in landscape it is
            // held like a handheld console: game in the middle, controls
            // beside it at thumb height. Half folded like a book, the game
            // takes the left page and the controller the right one.
            if context.duoSplit && !context.portrait && !partial {
                return BuiltInSkins.handheldLandscape(adapted, viewAspect: viewAspect, gameAspect: context.gameAspect)
            }
            if context.duoSplit {
                let gap = BuiltInSkins.foldGap(partiallyOpen: partial)
                return context.portrait
                    ? BuiltInSkins.splitPortrait(adapted, viewAspect: viewAspect, gameAspect: context.gameAspect,
                                                 gap: gap, gameBelow: context.duoGameBelow)
                    : BuiltInSkins.splitLandscape(adapted, viewAspect: viewAspect, gameAspect: context.gameAspect, gap: gap)
            }
            // Tela única: the phone layout in the Duo's proportions.
            adapted = context.portrait
                ? BuiltInSkins.reshaped(adapted, viewAspect: viewAspect)
                : BuiltInSkins.reshapedLandscape(adapted, viewAspect: viewAspect, gameAspect: context.gameAspect)
        }
        return BuiltInSkins.fitted(adapted, aspect: context.gameAspect, fullWidth: context.fullWidth)
    }
}
