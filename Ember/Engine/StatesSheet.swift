import SwiftUI
import UIKit

/// The save states of the running game: newest first, with the frame
/// each one was taken on. Tap to load, swipe to delete.
struct StatesSheet: View {
    let gameID: String
    let onLoad: (StateStore.SaveState) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var states: [StateStore.SaveState] = []

    var body: some View {
        NavigationStack {
            Group {
                if states.isEmpty {
                    ContentUnavailableView {
                        Label("Nenhum estado salvo", systemImage: "square.and.arrow.down.on.square")
                    } description: {
                        Text("Use Salvar estado no menu, andando pelo mapa. O Ember também salva sozinho quando você sai do app.")
                    }
                } else {
                    List {
                        ForEach(states) { state in
                            Button { onLoad(state) } label: { row(state) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            offsets.map { states[$0] }.forEach { StateStore.delete($0, gameID: gameID) }
                            states = StateStore.states(for: gameID)
                        }
                    }
                }
            }
            .navigationTitle("Estados")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Fechar")
                }
            }
        }
        .onAppear { states = StateStore.states(for: gameID) }
    }

    private func row(_ state: StateStore.SaveState) -> some View {
        HStack(spacing: 12) {
            Group {
                if let url = state.thumbnail, let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().interpolation(.none).scaledToFill()
                } else {
                    Color.black
                }
            }
            .frame(width: 96, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(state.isAuto ? String(localized: "Automático") : String(localized: "Estado salvo"))
                    .font(.body.weight(.semibold))
                Text(state.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.counterclockwise")
                .foregroundStyle(Theme.accent)
        }
        .contentShape(Rectangle())
    }
}
