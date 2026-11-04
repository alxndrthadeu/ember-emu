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
            if let url = game.coverURL, let image = UIImage(contentsOfFile: url.path) {
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
