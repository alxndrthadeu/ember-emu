import SwiftUI

/// The iCloud saves screens in a sheet of their own, with a way out.
struct CloudSavesSheet<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { dismiss() }
                    }
                }
        }
        .frame(width: 560, height: 520)
    }
}
