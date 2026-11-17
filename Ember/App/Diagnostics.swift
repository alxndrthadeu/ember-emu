import Foundation
import MetricKit
import SwiftUI

/// Reports iOS gathers about Ember on the player's own iPhone (MetricKit):
/// crashes, hangs, too much CPU or disk, heat, launch time. They stay on
/// the device, in Application Support/Diagnostics, until the player
/// shares one from Settings › Relatórios do sistema. Nothing is sent
/// anywhere by Ember.
final class Diagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = Diagnostics()
    /// The newest reports kept.
    private static let limit = 30

    static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    func start() {
        MXMetricManager.shared.add(self)
    }

    // Problems: crashes, hangs, CPU and disk exceptions. iOS delivers
    // them on the next launch, at most once a day.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            var kinds: [String] = []
            if !(payload.crashDiagnostics ?? []).isEmpty { kinds.append("crash") }
            if !(payload.hangDiagnostics ?? []).isEmpty { kinds.append("hang") }
            if !(payload.cpuExceptionDiagnostics ?? []).isEmpty { kinds.append("cpu") }
            if !(payload.diskWriteExceptionDiagnostics ?? []).isEmpty { kinds.append("disk") }
            save(payload.jsonRepresentation(), kind: kinds.isEmpty ? "diagnostic" : kinds.joined(separator: "+"),
                 date: payload.timeStampEnd)
        }
    }

    // Daily numbers: launch time, CPU, memory, heat, battery.
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            save(payload.jsonRepresentation(), kind: "metrics", date: payload.timeStampEnd)
        }
    }

    private func save(_ json: Data, kind: String, date: Date) {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
        try? json.write(to: Self.folder.appendingPathComponent("\(stamp) \(kind).json"), options: .atomic)
        let all = Self.reports()
        for old in all.dropFirst(Self.limit) { try? fm.removeItem(at: old.url) }
    }

    struct Report: Identifiable, Hashable {
        let url: URL
        let date: Date
        /// "crash", "hang", "cpu", "disk", "metrics"…
        let kind: String
        var id: URL { url }

        var isProblem: Bool { kind != "metrics" }
    }

    /// Newest first.
    static func reports() -> [Report] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension == "json" }.map { url in
            let name = url.deletingPathExtension().lastPathComponent
            let kind = name.split(separator: " ").last.map(String.init) ?? "diagnostic"
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return Report(url: url, date: date, kind: kind)
        }
        .sorted { $0.date > $1.date }
    }
}

/// Settings › Relatórios do sistema: what iOS reported about Ember.
struct DiagnosticsView: View {
    @State private var reports: [Diagnostics.Report] = []

    var body: some View {
        List {
            if reports.isEmpty {
                ContentUnavailableView {
                    Label("Nenhum relatório", systemImage: "stethoscope")
                } description: {
                    Text("O iOS manda ao Ember, uma vez por dia, um resumo de desempenho e o que deu errado: travamentos, aquecimento, uso alto de CPU. Ficam só neste iPhone.")
                }
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(reports) { report in
                        ShareLink(item: report.url) {
                            HStack(spacing: 12) {
                                Image(systemName: report.isProblem ? "exclamationmark.triangle.fill" : "chart.bar.doc.horizontal")
                                    .foregroundStyle(report.isProblem ? Theme.accent : Theme.secondaryText)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title(for: report))
                                        .foregroundStyle(Theme.primaryText)
                                    Text(report.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                } footer: {
                    Text("Toque para compartilhar um relatório, por exemplo ao relatar um problema no GitHub do Ember. Nada sai do iPhone sem você mandar.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Relatórios do sistema")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reports = Diagnostics.reports() }
    }

    private func title(for report: Diagnostics.Report) -> String {
        switch report.kind {
        case "metrics": String(localized: "Resumo do dia")
        case "crash": String(localized: "O app fechou sozinho")
        case "hang": String(localized: "O app travou")
        case "cpu": String(localized: "Uso alto de CPU")
        case "disk": String(localized: "Muita escrita no disco")
        default: String(localized: "Vários problemas")
        }
    }
}
