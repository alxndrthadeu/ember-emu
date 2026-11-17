import SwiftUI
import UIKit

/// The game's cover, or a warm placeholder with its initial.
struct CoverImage: View {
    let game: GameEntry
    var initialSize: CGFloat = 44

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.surface, Theme.surface2],
                           startPoint: .top, endPoint: .bottom)
            if let url = game.coverURL, let image = CoverCache.image(at: url) {
                Image(uiImage: image)
                    .resizable()
                    // Pixel art stays crisp when scaled.
                    .interpolation(.none)
                    .scaledToFill()
            } else {
                Text(String(game.title.prefix(1)).uppercased())
                    .font(.system(size: initialSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.secondaryText.opacity(0.8))
            }
        }
    }
}

/// A cover cut to a ratio. The ratio lives on a clear box: a filled
/// image would otherwise push the frame wider than its column.
struct CoverFrame: View {
    let game: GameEntry
    var ratio: CGFloat = 4 / 3
    var radius: CGFloat = Theme.cardRadius
    var initialSize: CGFloat = 44

    var body: some View {
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay { CoverImage(game: game, initialSize: initialSize) }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Covers and save pictures, decoded once: the library redraws its
/// cards often, and reading a file in `body` decodes it on every pass.
/// Keyed by path and modification date, so a new cover shows at once.
enum CoverCache {
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func image(at url: URL) -> UIImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let key = "\(url.path)@\(modified?.timeIntervalSince1970 ?? 0)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let loaded = UIImage(contentsOfFile: url.path) else { return nil }
        // Decoded now, not while scrolling.
        let image = loaded.preparingForDisplay() ?? loaded
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}
