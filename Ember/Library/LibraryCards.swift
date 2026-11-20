import SwiftUI

/// Explains, in the app's voice, how to open another game.
struct ReopenSheet: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            EmberFlame(size: 40)
                .padding(.top, 12)
            Text("Feche o Ember para abrir \(title)")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
            Text("O Ember abre um jogo por vez. Deslize de baixo para cima, feche o Ember no seletor de apps e abra de novo. Seus saves estão guardados.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            Button { dismiss() } label: {
                Text("Entendi").frame(maxWidth: .infinity)
            }
            .emberGlassProminentButton()
            .tint(Theme.accent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }
}

/// The last game played, big, with "Continuar" in âmbar.
struct ContinueCard: View {
    let game: GameEntry
    /// An automatic save state is waiting: the game opens right there.
    var resumes = false

    var body: some View {
        CoverFrame(game: game, ratio: 16 / 10, initialSize: 64)
            .overlay(alignment: .bottom) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if resumes {
                            Text("Volta de onde você parou")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.8))
                        } else if let lastPlayed = game.lastPlayed {
                            Text("Jogado \(lastPlayed.formatted(.relative(presentation: .named)))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    Spacer()
                    Label("Continuar", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.onHighlight)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .emberGlass(.regular.tint(Theme.highlight), in: Capsule())
                }
                .padding(14)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                   startPoint: .top, endPoint: .bottom))
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Theme.cardRadius,
                                                  bottomTrailingRadius: Theme.cardRadius,
                                                  style: .continuous))
            }
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Continuar \(game.title)")
    }
}

struct GameCard: View {
    let game: GameEntry
    /// Set while the game is being archived.
    var status: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverFrame(game: game)
                .overlay {
                    if let status {
                        ZStack {
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .fill(.black.opacity(0.45))
                            VStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Label(status, systemImage: "icloud.and.arrow.up")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .overlay(alignment: .topTrailing) { SyncBadge(id: game.id).padding(8) }
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
            Text(game.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
        }
        .contentShape(Rectangle())
    }
}

/// An archived game on the shelf: its cover, dimmed, with a cloud.
struct ArchivedCard: View {
    let record: ArchivedGame
    let status: String?
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Color.clear.aspectRatio(4 / 3, contentMode: .fit)
                    .overlay {
                        ZStack {
                            LinearGradient(colors: [Theme.surface, Theme.surface2], startPoint: .top, endPoint: .bottom)
                            if let url = GameCovers.url(forGameID: record.id,
                                                        folder: GameImporter.gamesFolder.appendingPathComponent(record.id)),
                               let image = CoverCache.image(at: url) {
                                Image(uiImage: image).resizable().interpolation(.none).scaledToFill()
                            } else {
                                Text(String(record.title.prefix(1)))
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .opacity(status == nil ? 0.45 : 0.25)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                VStack(spacing: 6) {
                    if let status {
                        if let progress {
                            ZStack {
                                Circle().stroke(Theme.primaryText.opacity(0.15), lineWidth: 4)
                                Circle().trim(from: 0, to: progress)
                                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .animation(.easeOut(duration: 0.3), value: progress)
                                Text("\(Int(progress * 100))%")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                            }
                            .frame(width: 44, height: 44)
                        } else {
                            ProgressView()
                        }
                        Text(status).font(.caption.weight(.semibold))
                    } else {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 26, weight: .semibold))
                        Text(ByteCountFormatter.string(fromByteCount: record.size, countStyle: .file))
                            .font(.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(Theme.primaryText)
            }
            Text(record.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
        }
        .contentShape(Rectangle())
    }
}

struct Banner<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .emberGlass(.regular, in: Capsule())
            .padding(.bottom, 8)
    }
}

/// A card that answers a tap and a long press, and shows it is being
/// touched (cards are not system buttons: the long press opens Ember's
/// own options sheet). VoiceOver reads it as one button.
struct CardPress: ViewModifier {
    let onTap: () -> Void
    let onLongPress: () -> Void
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .opacity(pressed && reduceMotion ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: pressed)
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.45, perform: {
                Haptics.tap()
                onLongPress()
            }, onPressingChanged: { pressed = $0 })
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }
}

extension View {
    func cardPress(onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) -> some View {
        modifier(CardPress(onTap: onTap, onLongPress: onLongPress))
    }
}
