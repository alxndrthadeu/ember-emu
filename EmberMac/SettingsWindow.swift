import AppKit
import SwiftUI

/// Ember › Ajustes… (⌘,): iCloud, the screen filter, RTPs and about.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 480),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: "Ajustes")
        window.contentView = NSHostingView(rootView: SettingsView().fontDesign(.rounded))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}

private struct SettingsView: View {
    @State private var iCloudSaves = SaveSync.isEnabled
    @State private var filter = ScreenFilter.current
    @State private var soundOn = UserDefaults.standard.object(forKey: "settings.gameSound") as? Bool ?? true
    @State private var importingRTP = false
    @Bindable private var library = MacLibrary.shared

    var body: some View {
        Form {
            Section {
                Toggle("Saves no iCloud", isOn: $iCloudSaves)
                    .onChange(of: iCloudSaves) {
                        UserDefaults.standard.set(iCloudSaves, forKey: SaveSync.enabledKey)
                        if iCloudSaves { library.syncSaves() }
                    }
            } header: {
                Text("iCloud")
            } footer: {
                Text("Os saves e estados de cada jogo vão para o iCloud e voltam no seu iPhone com o mesmo jogo. Os jogos não vão. Se um save mudar nos dois aparelhos, fica o mais recente e o outro vai para Backups.")
                    .foregroundStyle(.secondary)
            }

            Section("Jogo") {
                Picker("Filtro de tela", selection: $filter) {
                    ForEach(ScreenFilter.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: filter) { ScreenFilter.current = filter }
                Toggle("Som do jogo", isOn: $soundOn)
                    .onChange(of: soundOn) { UserDefaults.standard.set(soundOn, forKey: "settings.gameSound") }
            }

            Section {
                ForEach(RTPStore.Kind.allCases, id: \.self) { kind in
                    LabeledContent(kind.name) {
                        if RTPStore.isInstalled(kind) {
                            Label("Instalado", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.activeText)
                        } else {
                            Text("Não instalado").foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Importar RTP…") { importingRTP = true }
            } header: {
                Text("RTP")
            } footer: {
                Text("Alguns jogos antigos usam os gráficos e sons do RTP do RPG Maker. Importe a pasta do RTP (ou um .zip) uma vez.")
                    .foregroundStyle(.secondary)
            }

            Section("Sobre") {
                LabeledContent("Versão", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                LabeledContent("Motor", value: "mkxp-z")
                Link("Código no GitHub", destination: URL(string: "https://github.com/alxndrthadeu/ember-emu")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 480)
        .fileImporter(isPresented: $importingRTP, allowedContentTypes: [.folder, .zip], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result { library.importItems(urls) }
        }
    }
}
