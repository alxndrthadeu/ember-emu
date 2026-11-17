import SwiftUI

/// A PC keyboard drawn on screen, to pick the key a button or direction
/// presses (Teclado mode of a game's controls). Keys the game reads are
/// marked; each key shows which buttons already press it.
struct KeyboardPicker: View {
    /// What is being set: a button ("A") or a direction ("Cima").
    let title: String
    let selected: KeyboardKey?
    let gameKeys: [KeyboardKey]
    /// Button labels already on each key (scancode → ["A", "L2"]).
    let usedBy: [Int32: [String]]
    /// Ember's own actions, offered for buttons only.
    var specials: [GameAction] = []
    var selectedSpecial: GameAction?
    let onKey: (KeyboardKey) -> Void
    var onSpecial: (GameAction) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    // The keyboard fills the width; key labels and rows grow with the
    // text size, up to what a key can hold.
    @ScaledMetric(relativeTo: .subheadline) private var keyHeight: CGFloat = 46
    @ScaledMetric(relativeTo: .subheadline) private var letterSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var wordSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var cornerSize: CGFloat = 9

    /// Rows of (scancode, width in key units).
    private static let rows: [[(Int32, CGFloat)]] = [
        [(41, 1.3)] + (60...68).map { (Int32($0), 1) },               // Esc, F3–F11
        (30...39).map { (Int32($0), 1) } + [(42, 1.5)],               // 1–0, Backspace
        [(43, 1.4)] + [20, 26, 8, 21, 23, 28, 24, 12, 18, 19].map { (Int32($0), 1) },   // Tab, Q–P
        [4, 22, 7, 9, 10, 11, 13, 14, 15].map { (Int32($0), 1) } + [(40, 1.8)],         // A–L, Enter
        [(225, 1.8)] + [29, 27, 6, 25, 5, 17, 16].map { (Int32($0), 1) },               // Shift, Z–M
        [(224, 1.3), (226, 1.3), (44, 4.2), (80, 1), (82, 1), (81, 1), (79, 1)],         // Ctrl Alt Space ← ↑ ↓ →
        [(74, 1.6), (77, 1.6), (75, 1.9), (78, 1.9)],                                    // Home End PgUp PgDn
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    keyboard
                    legend
                    if !specials.isEmpty { specialRow }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private var keyboard: some View {
        GeometryReader { proxy in
            // The widest row (Ctrl … →, 7 keys and 11.8 units) fills the width.
            let unit = (proxy.size.width - 4 * 6) / 11.8
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.rows.indices, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(Self.rows[row], id: \.0) { scancode, width in
                            keycap(KeyboardKey(scancode: scancode), width: unit * width + 4 * (width - 1))
                        }
                    }
                }
            }
        }
        .frame(height: 7 * keyHeight + 6 * 6)
    }

    private func keycap(_ key: KeyboardKey, width: CGFloat) -> some View {
        let isSelected = key == selected && selectedSpecial == nil
        let isGameKey = gameKeys.contains(key)
        let used = usedBy[key.scancode] ?? []
        return Button {
            Haptics.tap()
            onKey(key)
            dismiss()
        } label: {
            ZStack(alignment: .topTrailing) {
                Text(verbatim: Self.shortName(key))
                    .font(.system(size: Self.shortName(key).count > 1 ? wordSize : letterSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(isSelected ? Theme.onAccent : Theme.primaryText)
                    .frame(width: width, height: keyHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isSelected ? Theme.accent : Theme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(isGameKey ? Theme.highlightEdge : Theme.surface2, lineWidth: isGameKey ? 2 : 1)
                    )
                if isGameKey && !isSelected {
                    // Not by color alone: a dot marks the game's keys.
                    Circle().fill(Theme.highlightEdge)
                        .frame(width: 5, height: 5)
                        .padding(5)
                        .frame(width: width, height: keyHeight, alignment: .bottomLeading)
                }
                if !used.isEmpty {
                    Text(verbatim: used.joined(separator: " "))
                        .font(.system(size: cornerSize, weight: .heavy, design: .rounded))
                        .foregroundStyle(isSelected ? Theme.onAccent : Theme.activeText)
                        .padding(.horizontal, 3)
                        .padding(.top, 2)
                        .lineLimit(1)
                        .frame(maxWidth: width - 4, alignment: .trailing)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: key.name))
        .accessibilityValue(accessibilityValue(isGameKey: isGameKey, used: used))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func accessibilityValue(isGameKey: Bool, used: [String]) -> String {
        var parts: [String] = []
        if isGameKey { parts.append(String(localized: "Usada pelo jogo")) }
        if !used.isEmpty { parts.append(String(localized: "Já em \(used.joined(separator: ", "))")) }
        return parts.joined(separator: "; ")
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !gameKeys.isEmpty {
                Label {
                    Text("Contorno âmbar e ponto: teclas que este jogo usa")
                } icon: {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.highlightEdge, lineWidth: 2)
                        .frame(width: 14, height: 14)
                }
            }
            Label {
                Text("No canto: botões que já apertam a tecla")
            } icon: {
                Text(verbatim: "A").font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.activeText).frame(width: 14, height: 14)
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.secondaryText)
    }

    private var specialRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ações do Ember")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            FlowRow(spacing: 8) {
                ForEach(specials) { action in
                    Button {
                        Haptics.tap()
                        onSpecial(action)
                        dismiss()
                    } label: {
                        Text(action.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(selectedSpecial == action ? Theme.onAccent : Theme.primaryText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(selectedSpecial == action ? Theme.accent : Theme.surface))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Short names that fit a keycap.
    static func shortName(_ key: KeyboardKey) -> String {
        switch key.scancode {
        case 42: "⌫"
        case 225: "Shift"
        case 75: "PgUp"
        case 78: "PgDn"
        default: key.name
        }
    }
}

/// Wraps its children onto new lines when a line is full.
private struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
