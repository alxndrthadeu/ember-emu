import SwiftUI
import UniformTypeIdentifiers

/// The ways to bring games in: a hearth card with the main road (the
/// Files app), the browser transfer over Wi-Fi, a short list of other
/// roads and a drop zone. Dropping files anywhere on the screen works.
struct ImportView: View {
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var wifi = WifiTransfer.shared
    @State private var showingPicker = false
    @State private var sheet: InfoSheet?
    @State private var notice: String?
    @State private var dropTargeted = false
    @State private var copied = false

    enum InfoSheet: String, Identifiable {
        case help, rtp, computer
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hearthCard
                    section(String(localized: "Pelo navegador")) { wifiCard }
                    section(String(localized: "Outros caminhos")) { otherRoads }
                    dropZone
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Importar")
            .onDrop(of: ProviderImport.acceptedTypes, isTargeted: $dropTargeted) { providers in
                Task { await importProviders(providers, emptyMessage: String(localized: "Nada do que foi solto parece um jogo, RTP, skin ou save.")) }
                return true
            }
            #if DEBUG
            .onAppear {
                // Development aid: EMBER_SHOW=computer|rtp opens that sheet.
                switch ProcessInfo.processInfo.environment["EMBER_SHOW"] {
                case "computer": sheet = .computer
                case "rtp": sheet = .rtp
                default: break
                }
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .help } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel("Ajuda")
                }
            }
        }
        .fileImporter(isPresented: $showingPicker,
                      allowedContentTypes: UTType.importable,
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            library.importItems(urls)
            AppRouter.shared.tab = .library
        }
        .sheet(item: $sheet) { which in
            NavigationStack {
                switch which {
                case .help: ImportHelpView()
                case .rtp: RTPInfoView { sheet = nil; showingPicker = true }
                case .computer: ComputerInfoView { sheet = nil; WifiTransfer.shared.start() }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Importar", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
        .alert("Não deu certo", isPresented: Binding(get: { wifi.lastError != nil }, set: { if !$0 { wifi.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(wifi.lastError ?? "")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .textCase(.uppercase)
                .padding(.leading, 6)
            content()
        }
    }

    // MARK: - The hearth: the main road

    private var hearthCard: some View {
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                EmberFlame(size: 30)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(Theme.highlight.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Traga seus jogos")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text("RPG Maker XP, VX e VX Ace")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            HStack(spacing: 6) {
                ForEach([".zip", ".rar", ".7z", ".exe", String(localized: "pasta")], id: \.self) { format in
                    Text(verbatim: format)
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(Theme.primaryText.opacity(0.8))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.surface2.opacity(0.8)))
                }
            }
            .accessibilityElement(children: .combine)

            Button { showingPicker = true } label: {
                Label("Escolher no Arquivos", systemImage: "folder.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .emberGlassProminentButton()
            .tint(Theme.accent)
            .controlSize(.large)

            Text("Também servem RTP, skins e saves. O jogo pode estar dentro de subpastas.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Warm light from the flame's side, cut to the card's shape.
        .background {
            RadialGradient(colors: [Theme.highlight.opacity(0.28), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 260)
                .clipShape(shape)
        }
        .emberGlass(.regular, in: shape)
        .padding(.top, 6)
    }

    // MARK: - Wi-Fi

    private var wifiCard: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RoadIcon(icon: "wifi", tint: Theme.active)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Enviar pelo Wi-Fi")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    Text(wifi.isOn ? String(localized: "Ligado, esperando arquivos") : String(localized: "De um computador na mesma rede"))
                        .font(.caption)
                        .foregroundStyle(wifi.isOn ? Theme.active : Theme.secondaryText)
                }
                Spacer(minLength: 0)
                Toggle("Enviar pelo Wi-Fi", isOn: Binding(get: { wifi.isOn }, set: { wifi.setOn($0) }))
                    .labelsHidden()
                    .tint(Theme.active)
            }

            if wifi.isOn, let address = wifi.address {
                // The address as a ticket to copy into the browser.
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Abra no navegador")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .textCase(.uppercase)
                        Text(verbatim: address)
                            .font(.title3.monospaced().weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 8)
                    Button {
                        UIPasteboard.general.string = "http://\(address)"
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.body.weight(.semibold))
                            .frame(width: 22, height: 22)
                    }
                    .emberGlassButton()
                    .accessibilityLabel(copied ? String(localized: "Copiado") : String(localized: "Copiar endereço"))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.active.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                )
                if let receiving = wifi.receiving {
                    Label(String(localized: "Recebendo \(receiving)…"), systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            } else if !wifi.isOn {
                Text("Ligue, abra o endereço no navegador do computador e mande arquivos ou a pasta inteira de um jogo.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .emberGlass(.regular, in: shape)
        .animation(.easeInOut(duration: 0.25), value: wifi.isOn)
        .animation(.easeInOut(duration: 0.25), value: wifi.address)
    }

    // MARK: - Other roads

    private var otherRoads: some View {
        VStack(spacing: 0) {
            RoadRow(icon: "doc.on.clipboard.fill", tint: Theme.highlight,
                    title: String(localized: "Colar da área de transferência"),
                    detail: String(localized: "Um arquivo copiado no Mac ou no Arquivos")) {
                Task { await pasteFromClipboard() }
            }
            Divider().padding(.leading, 64)
            RoadRow(icon: "cable.connector", tint: Theme.secondaryText,
                    title: String(localized: "Do computador, com cabo"),
                    detail: String(localized: "Mac, Windows ou Linux")) {
                sheet = .computer
            }
            Divider().padding(.leading, 64)
            if LibraryStore.demoFolder != nil {
                RoadRow(icon: "sparkles", tint: Theme.highlight,
                        title: String(localized: "Jogo de exemplo"),
                        detail: String(localized: "A Última Brasa, um jogo pequeno feito para o Ember"),
                        badge: library.hasDemo ? String(localized: "Na estante") : nil) {
                    library.installDemo()
                    AppRouter.shared.tab = .library
                }
                Divider().padding(.leading, 64)
            }
            RoadRow(icon: "shippingbox.fill", tint: Theme.accent,
                    title: String(localized: "RTP"),
                    detail: String(localized: "Gráficos e sons padrão que muitos jogos usam"),
                    badge: rtpBadge) {
                sheet = .rtp
            }
        }
        .emberGlass(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var rtpBadge: String? {
        let installed = RTPStore.Kind.allCases.filter(RTPStore.isInstalled)
        return installed.isEmpty ? nil : installed.map(\.shortName).joined(separator: " · ")
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: dropTargeted ? "flame.fill" : "arrow.down.to.line")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(dropTargeted ? Theme.accent : Theme.secondaryText)
                .contentTransition(.symbolEffect(.replace))
            Text(dropTargeted ? String(localized: "Pode soltar") : String(localized: "Ou solte arquivos aqui"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(dropTargeted ? Theme.accent : Theme.primaryText)
            Text("Arraste de outro app, com a tela dividida ou no iPad")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(dropTargeted ? Theme.highlight.opacity(0.12) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(dropTargeted ? Theme.accent : Theme.surface2,
                              style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
        )
        .animation(.easeInOut(duration: 0.2), value: dropTargeted)
    }

    // MARK: - Clipboard and drop

    private func pasteFromClipboard() async {
        await importProviders(UIPasteboard.general.itemProviders,
                              emptyMessage: String(localized: "A área de transferência não tem um jogo, RTP, skin ou save. Copie o arquivo no Mac ou no app Arquivos e tente de novo."))
    }

    private func importProviders(_ providers: [NSItemProvider], emptyMessage: String) async {
        let urls = await ProviderImport.files(from: providers)
        if urls.isEmpty {
            notice = emptyMessage
            return
        }
        library.importItems(urls, removeSources: true)
        AppRouter.shared.tab = .library
    }
}

// MARK: - Pieces

/// A small round icon for a road.
private struct RoadIcon: View {
    let icon: String
    let tint: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(Circle().fill(tint.opacity(0.16)))
            .accessibilityHidden(true)
    }
}

/// One row of "Outros caminhos".
private struct RoadRow: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String
    var badge: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RoadIcon(icon: icon, tint: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.primaryText)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if let badge {
                    Text(verbatim: badge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.active)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.active.opacity(0.14)))
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheets

private struct ImportHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("O que dá para importar") {
                Label("Jogos de RPG Maker XP, VX e VX Ace: .zip, .rar, .7z, .exe autoextraível ou a pasta do jogo", systemImage: "gamecontroller")
                Label("RTP, a pasta com os gráficos e sons padrão", systemImage: "shippingbox")
                Label("Skins .deltaskin e .manicskin", systemImage: "paintpalette")
                Label("Saves pelo painel do jogo, na Biblioteca", systemImage: "externaldrive")
            }
            Section {
                Text("O Ember encontra o jogo mesmo dentro de subpastas. Se quiser, ele manda o arquivo compactado para a lixeira depois de importar, para liberar espaço (Ajustes › Importação).")
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Ajuda")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
    }
}

private struct RTPInfoView: View {
    var importAction: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(RTPStore.Kind.allCases) { kind in
                    HStack {
                        Text(kind.name)
                        Spacer()
                        if RTPStore.isInstalled(kind) {
                            Label("Instalado", systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(Theme.active)
                        } else {
                            Text("Não instalado")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            } footer: {
                Text("Muitos jogos contam com os gráficos e sons padrão do RPG Maker (o RTP), que o Ember não traz. Importe a pasta do RTP, ou um .zip dela, pela aba Importar: o Ember reconhece a versão e todos os jogos dela passam a usar. No Windows, ela fica em Arquivos Comuns › Enterbrain › RGSS.")
            }
            Section {
                Button {
                    importAction()
                } label: {
                    Label("Importar RTP do Arquivos", systemImage: "folder.badge.plus")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("RTP")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
    }
}

/// How to copy games from a computer: the Finder on a Mac, Apple
/// Devices (or iTunes) on Windows; Linux has no Apple app, so it gets
/// the browser transfer, and ifuse for the command line.
private struct ComputerInfoView: View {
    var useWifi: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var system = System.mac

    enum System: String, CaseIterable, Identifiable {
        case mac, windows, linux
        var id: String { rawValue }
        var name: String {
            switch self {
            case .mac: "Mac"
            case .windows: "Windows"
            case .linux: "Linux"
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Sistema", selection: $system) {
                    ForEach(System.allCases) { Text(verbatim: $0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            switch system {
            case .mac:
                Section {
                    Step(number: 1, text: String(localized: "Conecte o iPhone ao Mac com o cabo. Depois da primeira vez, o mesmo Wi-Fi basta."))
                    Step(number: 2, text: String(localized: "No Finder, escolha o iPhone na barra lateral e abra a aba Arquivos."))
                    Step(number: 3, text: String(localized: "Arraste o .zip, .rar, .7z ou a pasta do jogo para o Ember."))
                    Step(number: 4, text: String(localized: "Abra o Ember. O jogo aparece na Biblioteca."))
                }
            case .windows:
                Section {
                    Step(number: 1, text: String(localized: "Instale o app Dispositivos Apple pela Microsoft Store (ou use o iTunes)."))
                    Step(number: 2, text: String(localized: "Conecte o iPhone com o cabo e toque em Confiar, se o iPhone perguntar."))
                    Step(number: 3, text: String(localized: "No app, escolha o iPhone e abra Arquivos. Selecione o Ember."))
                    Step(number: 4, text: String(localized: "Arraste o .zip, .rar ou .7z do jogo para o Ember e abra o Ember. O jogo aparece na Biblioteca."))
                } footer: {
                    Text("O Windows não copia pastas por esse caminho: compacte a pasta do jogo num .zip antes, ou use o Wi-Fi.")
                }
            case .linux:
                Section {
                    Text("A Apple não tem app para Linux. O jeito mais fácil é mandar pelo navegador, no mesmo Wi-Fi: funciona com arquivos e pastas inteiras.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                    Button {
                        useWifi()
                    } label: {
                        Label("Ligar o envio pelo Wi-Fi", systemImage: "wifi")
                    }
                }
                Section {
                    Text(verbatim: "ifuse --documents \(Bundle.main.bundleIdentifier ?? "com.alexandrethadeu.ember") ~/ember")
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                } header: {
                    Text("Pelo terminal, com cabo")
                } footer: {
                    Text("Com libimobiledevice e ifuse instalados, esse comando monta a pasta do Ember. Copie o jogo para dentro dela, desmonte com fusermount -u ~/ember e abra o Ember.")
                }
            }

            Section {
            } footer: {
                Text("No Safari, no Arquivos ou num app de mensagens também dá: toque no arquivo, depois em Compartilhar e em Ember.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Do computador")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
    }
}

private struct Step: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.accent))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Item providers (clipboard, drag and drop)

@MainActor
enum ProviderImport {
    static let acceptedTypes: [UTType] = [.fileURL, .folder] + UTType.importable + [.deltaSkin, .manicSkin]

    /// Copies each provided file to a temporary place Ember owns (the
    /// provider's copy goes away when its callback returns). Providers
    /// with nothing Ember can import are skipped.
    static func files(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await file(from: provider) { urls.append(url) }
        }
        return urls
    }

    private static func file(from provider: NSItemProvider) async -> URL? {
        let wanted = UTType.importable + [.deltaSkin, .manicSkin]
        guard let type = provider.registeredContentTypes.first(where: { registered in
            wanted.contains { registered.conforms(to: $0) }
        }) else { return nil }
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                guard let url else { return continuation.resume(returning: nil) }
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("Pasted-\(UUID().uuidString)", isDirectory: true)
                let target = folder.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: target)
                    continuation.resume(returning: target)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

extension UTType {
    static let rar = UTType(importedAs: "com.rarlab.rar-archive")
    static let sevenZip = UTType(importedAs: "org.7-zip.7-zip-archive")
    static let deltaSkin = UTType(importedAs: "com.rileytestut.delta.skin")
    static let manicSkin = UTType(importedAs: "com.alexandrethadeu.ember.manicskin")

    /// Windows .exe: self-extracting archives (installers that carry the game).
    static let windowsProgram = UTType(filenameExtension: "exe") ?? .data
    /// What the game importer takes.
    static let importable: [UTType] = [.zip, .rar, .sevenZip, .windowsProgram, .folder]
    /// What the skin importer takes.
    static let skins: [UTType] = [.deltaSkin, .manicSkin, .zip, .folder]
}
