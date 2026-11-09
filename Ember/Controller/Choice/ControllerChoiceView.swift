import SwiftUI

/// "Como você quer jogar?": shown after a game is imported, with the
/// controller its scripts suggest already picked, and from the game's
/// options. The controllers slide sideways, one big card each, drawn
/// for this device (an open iPhone Duo shows its own layout).
struct ControllerChoiceView: View {
    let game: GameEntry

    @Environment(\.dismiss) private var dismiss
    @State private var selection: ControllerType?

    init(game: GameEntry) {
        self.game = game
        _selection = State(initialValue: ControllerTypeStore.type(for: game))
    }

    private var suggested: ControllerType? { ControllerTypeStore.detected(for: game.id) }
    private var current: ControllerType { selection ?? .classic2 }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Como você quer jogar?")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.primaryText)
                Text(game.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 24)
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(ControllerType.allCases) { type in
                        card(type)
                            .containerRelativeFrame(.horizontal) { width, _ in width * 0.74 }
                            .id(type)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .safeAreaPadding(.horizontal, 48)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection)
            .fixedSize(horizontal: false, vertical: true)

            dots

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button {
                    ControllerTypeStore.set(current, for: game.id)
                    Haptics.tap()
                    dismiss()
                } label: {
                    Text("Usar \(current.title)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .emberGlassProminentButton()
                .tint(Theme.accent)
                .controlSize(.large)

                Text("Dá para trocar depois, no painel do jogo (segure a capa na estante). Os botões seguem o perfil de controle do jogo.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(Theme.background.ignoresSafeArea())
        .onDisappear {
            // Closed without a choice: the suggestion stays, no new question.
            ControllerTypeStore.markAsked(game.id)
        }
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(ControllerType.allCases) { type in
                Capsule()
                    .fill(type == current ? Theme.accent : Theme.secondaryText.opacity(0.3))
                    .frame(width: type == current ? 18 : 7, height: 7)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityHidden(true)
    }

    private func card(_ type: ControllerType) -> some View {
        let selected = current == type
        return Button {
            withAnimation(.snappy) { selection = type }
            Haptics.tap()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                ControllerPreview(type: type)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("Recomendado para este jogo")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.onHighlight)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.highlight, in: Capsule())
                    .opacity(type == suggested ? 1 : 0)
                    .accessibilityHidden(type != suggested)
                Label(type.title, systemImage: type.icon)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(type.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(3, reservesSpace: true)
            }
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Color.clear, lineWidth: 3)
            }
            .scaleEffect(selected ? 1 : 0.94)
            .animation(.snappy, value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A picture of a controller type on this device: Ember Laranja's
/// layout from ControllerLayouts (the same the game screen uses), drawn
/// at full size and scaled down, cropped to the part with the controls.
struct ControllerPreview: View {
    let type: ControllerType

    var body: some View {
        let screen = UIScreen.main.bounds.size
        var context = ControllerContext.current(portrait: screen.height >= screen.width, keyboard: true, type: type)
        context.gameAspect = 4 / 3
        let layout = ControllerLayouts.layout(for: BuiltInSkins.ember, in: context)
        let crop = Self.controlsArea(of: layout)
        return Color.clear
            .aspectRatio(crop.width / crop.height, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                GeometryReader { geo in
                    BuiltInSkinArt(style: .ember, layout: layout, pressed: [], held: [:])
                        .frame(width: layout.mappingSize.width, height: layout.mappingSize.height)
                        .offset(x: -crop.minX, y: -crop.minY)
                        .scaleEffect(geo.size.width / crop.width, anchor: .topLeading)
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The controls' bounding box, full width, with a margin.
    static func controlsArea(of layout: SkinLayout) -> CGRect {
        let frames = layout.items.filter { $0.inputs.first != .swapScreens }.map(\.frame)
        guard let first = frames.first else { return CGRect(origin: .zero, size: layout.mappingSize) }
        let box = frames.dropFirst().reduce(first) { $0.union($1) }
        let top = max(box.minY - 14, 0)
        let bottom = min(box.maxY + 14, layout.mappingSize.height)
        return CGRect(x: 0, y: top, width: layout.mappingSize.width, height: bottom - top)
    }
}
