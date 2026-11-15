import SwiftUI
import UniformTypeIdentifiers

/// The ways to bring games in: a hearth card with the main road (the
/// Files app), the browser transfer over Wi-Fi, a short list of other
/// roads and a drop zone. Dropping files anywhere on the screen works.
struct ImportView: View {
    @Bindable private var library = LibraryStore.shared
    @Bindable private var wifi = WifiTransfer.shared
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
