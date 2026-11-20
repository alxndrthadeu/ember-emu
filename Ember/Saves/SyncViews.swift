import SwiftUI

/// The iCloud state of a game's saves, in the corner of its cover.
struct SyncBadge: View {
    let id: String

    var body: some View {
        if let state = SyncStatus.shared.state(for: id) {
            let (icon, label): (String, String) = switch state {
            case .upToDate: ("checkmark.icloud.fill", String(localized: "Saves em dia no iCloud"))
            case .sending: ("icloud.and.arrow.up.fill", String(localized: "Enviando saves"))
            case .incoming: ("icloud.and.arrow.down.fill", String(localized: "Save novo chegando"))
            case .conflict: ("exclamationmark.icloud.fill", String(localized: "Saves de dois aparelhos: ficou o mais recente"))
            }
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(state == .upToDate ? Theme.activeText : Theme.accent)
                .padding(6)
                .background(Circle().fill(Theme.surface.opacity(0.92)))
                .accessibilityLabel(label)
        }
    }
}

/// "Save sincronizado" at the top of the library, for a few seconds.
struct SyncToast: View {
    let text: String
    var busy = false

    var body: some View {
        HStack(spacing: 8) {
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundStyle(Theme.activeText)
            }
            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .emberGlass(.regular, in: Capsule())
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .onAppear { AccessibilityNotification.Announcement(text).post() }
    }
}
