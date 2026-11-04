import SwiftUI

/// Every session played, grouped by day, as in Manic EMU's history.
struct HistoryView: View {
    /// Opens a game; the library decides whether it can run now.
    let onOpen: (GameEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = LibraryStore.shared
    @State private var sessions = PlayHistory.sessions
    @State private var confirmingClear = false

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView {
                        Label("Nenhuma partida ainda", systemImage: "clock")
                    } description: {
                        Text("Cada vez que você jogar, a partida aparece aqui com a duração.")
                    }
                } else {
                    List {
                        ForEach(days, id: \.self) { day in
                            Section(dayTitle(day)) {
                                ForEach(sessions(on: day)) { session in
                                    row(session)
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Histórico")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Fechar")
                }
                if !sessions.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Limpar") { confirmingClear = true }
                    }
                }
            }
            .confirmationDialog("Limpar o histórico?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Limpar histórico", role: .destructive) {
                    PlayHistory.clear()
                    sessions = []
                    library.reload()
                }
            } message: {
                Text("Os jogos e os saves não mudam.")
            }
        }
    }

    @ViewBuilder
    private func row(_ session: PlaySession) -> some View {
        let game = library.games.first { $0.id == session.gameID }
        Button {
            guard let game else { return }
            dismiss()
            onOpen(game)
        } label: {
            HStack(spacing: 12) {
                Group {
                    if let game {
                        CoverFrame(game: game, radius: 8, initialSize: 18)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.surface2)
                            .aspectRatio(4 / 3, contentMode: .fit)
                    }
                }
                .frame(width: 64)

                VStack(alignment: .leading, spacing: 2) {
                    Text(game?.title ?? session.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Text("\(session.start.formatted(date: .omitted, time: .shortened)) · \(durationText(session.duration))")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    if game == nil {
                        Text("Jogo removido da biblioteca")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
                if game != nil {
                    Image(systemName: "play.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(game == nil)
        .listRowBackground(Theme.surface)
    }

    private var days: [Date] {
        Array(Set(sessions.map { Calendar.current.startOfDay(for: $0.start) })).sorted(by: >)
    }

    private func sessions(on day: Date) -> [PlaySession] {
        sessions.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return String(localized: "Hoje") }
        if Calendar.current.isDateInYesterday(day) { return String(localized: "Ontem") }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// "Menos de 1 min", "32 min", "2 h 5 min".
func durationText(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 1 { return String(localized: "menos de 1 min") }
    if minutes < 60 { return String(localized: "\(minutes) min") }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? String(localized: "\(hours) h") : String(localized: "\(hours) h \(rest) min")
}
