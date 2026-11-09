import UIKit

/// Draws an imported skin where its artist did not: on an iPhone Duo,
/// in an orientation the skin lacks, or a bottom-only skin on a full
/// screen. Uses the skin's converted parts (EmberSkinConverter).
enum SkinRecomposer {
    /// Ember's layout for the context, each button drawn from the skin's
    /// own picture of it. Buttons the skin has no picture for (the
    /// keyboard, a DS window) are drawn plainly by Ember.
    static func recompose(_ skin: Skin, in context: ControllerContext) -> SkinLayout {
        var layout = ControllerLayouts.layout(for: BuiltInSkins.ember, in: context)
        guard let package = EmberSkinConverter.package(for: skin) else { return layout }
        layout.artwork = nil
        layout.backdrop = package.backdrop
        layout.items = layout.items.map { item in
            var item = item
            item.sprite = package.part(for: item).flatMap(package.url)
            if item.kind == .stick, let thumb = package.thumb {
                item.thumb = package.url(thumb)
                let side = min(item.frame.width, item.frame.height) * 0.62
                item.thumbSize = CGSize(width: side * thumb.aspect, height: side)
            }
            return item
        }
        return layout
    }

    /// A skin drawn for the bottom of the screen (no game frame in it):
    /// placed at the bottom of a full-screen layout, the game above it,
    /// the rest of the screen in the skin's own top color.
    static func anchoredAtBottom(_ own: SkinLayout, skin: Skin, in context: ControllerContext) -> SkinLayout {
        let width = own.mappingSize.width
        let height = (width * context.screenAspect).rounded()
        let drop = height - own.mappingSize.height
        guard drop > 40 else { return own }
        var layout = own
        layout.mappingSize = CGSize(width: width, height: height)
        layout.artworkFrame = CGRect(x: 0, y: drop, width: width, height: own.mappingSize.height)
        layout.items = own.items.map { item in
            var item = item
            item.frame.origin.y += drop
            return item
        }
        let ratio = max(context.gameAspect ?? 4 / 3, 0.5)
        let top = height * 0.07
        let room = CGRect(x: 0, y: top, width: width, height: drop - top - 6)
        var w = room.width, h = w / ratio
        if h > room.height { h = room.height; w = h * ratio }
        layout.screen = CGRect(x: (width - w) / 2, y: top, width: w, height: h)
        if let package = EmberSkinConverter.package(for: skin) {
            let backdrop = package.backdrop
            layout.backdrop = SkinBackdrop(top: backdrop.top, bottom: backdrop.top, bezel: backdrop.bezel)
        }
        return layout
    }
}
