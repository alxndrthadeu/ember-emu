import SwiftUI
import UniformTypeIdentifiers

/// The Ajustes tab: skins, controls, game and app settings.
struct SettingsView: View {
    @ObservedObject private var skins = SkinStore.shared
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var performance = PerformanceModel.shared
    @ObservedObject private var controllers = ControllerMonitor.shared

    @State private var haptics = AppSettings.haptics
    @State private var landscapeOpacity = AppSettings.landscapeOpacity
    @State private var hideWithController = AppSettings.hideControlsWithController
    @State private var fastForwardSpeed = AppSettings.fastForwardSpeed
    @State private var pauseOnBackground = AppSettings.pauseOnBackground
    @State private var deleteArchive = AppSettings.deleteArchiveAfterImport

    @State private var importingSkin = false
    @State private var pendingDelete: Skin?
    @State private var skinError: String?

    var body: some View {
        NavigationStack {
            Form {
                skinsSection
                Section {
                    NavigationLink {
                        ProfilesView()
                    } label: {
                        Label("Perfis de controle", systemImage: "gamecontroller")
                    }
                    Toggle("Vibração ao tocar", isOn: $haptics)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Transparência na paisagem")
                            Spacer()
                            Text("\(Int(landscapeOpacity * 100))%")
                                .foregroundStyle(Theme.secondaryText)
                                .monospacedDigit()
                        }
                        Slider(value: $landscapeOpacity, in: 0.25...1, step: 0.05)
                    }
                    Toggle("Esconder botões com controle", isOn: $hideWithController)
                } header: {
                    Text("Controles")
                } footer: {
                    Text("A transparência vale para skins que permitem ver o jogo por trás dos botões. Com um controle de Xbox, PlayStation ou MFi conectado, os botões da tela somem na paisagem e a engrenagem fica num canto.")
                }

                Section {
                    if controllers.devices.isEmpty {
                        Label("Nenhum controle conectado", systemImage: "gamecontroller")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(controllers.devices) { device in
                        HStack {
                            Label(device.name, systemImage: device.symbol)
                            Spacer()
                            if let battery = device.battery {
                                Text(battery)
                                    .foregroundStyle(Theme.secondaryText)
                                    .monospacedDigit()
                            }
                        }
                    }
                } header: {
                    Text("Controles conectados")
                } footer: {
                    Text("Bluetooth: ponha o controle em modo de pareamento e escolha-o em Ajustes do iPhone › Bluetooth. USB: ligue o cabo (USB-C direto, ou o adaptador Lightning para USB). Funcionam controles de Xbox, PlayStation, Switch Pro e MFi, e teclados, que chegam ao jogo como o teclado de um computador. Os botões seguem o perfil de controle de cada jogo.")
                }
                .onAppear { controllers.refresh() }

                Section {
                    Picker("Avanço rápido", selection: $fastForwardSpeed) {
                        Text("2x").tag(2)
                        Text("3x").tag(3)
                        Text("5x").tag(5)
                    }
                    Toggle("Pausar ao sair do app", isOn: $pauseOnBackground)
                    Toggle("Mostrar desempenho (FPS, CPU, memória)", isOn: $performance.enabled)
                } header: {
                    Text("Jogo")
                } footer: {
                    Text("O avanço rápido é a velocidade dos botões de acelerar das skins. No menu da engrenagem você escolhe a velocidade na hora.")
                }

                Section {
                    Toggle("Apagar o arquivo depois de importar", isOn: $deleteArchive)
                } header: {
                    Text("Importação")
                } footer: {
                    Text("Jogos ocupam bastante espaço. Depois de importar um .zip, .rar ou .7z, o Ember manda o arquivo original para Apagados Recentemente, no app Arquivos. Dá para recuperar por 30 dias.")
                }

                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Ajustes")
        }
        .onChange(of: haptics) { AppSettings.haptics = haptics }
        .onChange(of: landscapeOpacity) { AppSettings.landscapeOpacity = landscapeOpacity }
        .onChange(of: hideWithController) { AppSettings.hideControlsWithController = hideWithController }
        .onChange(of: fastForwardSpeed) { AppSettings.fastForwardSpeed = fastForwardSpeed }
        .onChange(of: pauseOnBackground) { AppSettings.pauseOnBackground = pauseOnBackground }
        .onChange(of: deleteArchive) { AppSettings.deleteArchiveAfterImport = deleteArchive }
        .fileImporter(isPresented: $importingSkin, allowedContentTypes: UTType.skins,
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            do {
                try skins.importSkin(from: url)
            } catch {
                skinError = error.localizedDescription
            }
        }
        .alert("Não deu certo", isPresented: Binding(get: { skinError != nil }, set: { if !$0 { skinError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(skinError ?? "")
        }
        .confirmationDialog("Apagar a skin \(pendingDelete?.name ?? "")?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Apagar skin", role: .destructive) {
                if let skin = pendingDelete { skins.delete(skin) }
            }
        }
    }

    // MARK: Skins

    private var skinsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(skins.all) { skin in
                        SkinTile(skin: skin, selected: skin.id == skins.selectedID)
                            .onTapGesture {
                                Haptics.tap()
                                skins.selectedID = skin.id
                            }
                            .contextMenu {
                                if !skin.isBuiltIn {
                                    Button(role: .destructive) { pendingDelete = skin } label: {
                                        Label("Apagar", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
                .padding(.vertical, 6)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            Button {
                importingSkin = true
            } label: {
                Label("Importar skin", systemImage: "square.and.arrow.down")
            }
            Link(destination: URL(string: "https://noah978.gitbook.io/delta-docs/skins")!) {
                Label("Como criar sua própria skin", systemImage: "paintbrush")
            }
        } header: {
            Text("Skins")
        } footer: {
            Text("O Ember lê skins do Delta e do Manic EMU (.deltaskin, .manicskin). Procure por “GBA deltaskin”: há muitas, de graça e pagas, feitas por artistas independentes. Toque numa skin para usar, ou segure para apagar uma importada. Skins sem paisagem usam a Ember Laranja quando o iPhone deita.")
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section("Sobre") {
            LabeledContent("Versão", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            LabeledContent("Motor", value: "mkxp-z")
            NavigationLink("Licenças de código aberto") { LicensesView() }
        }
    }
}

/// A skin's portrait art in a small phone-shaped frame.
private struct SkinTile: View {
    let skin: Skin
    let selected: Bool

    var body: some View {
        VStack(spacing: 8) {
            preview
                .frame(width: 92, height: 199)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(selected ? Theme.accent : Theme.surface2, lineWidth: selected ? 3 : 1))
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
                Text(skin.name)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.primaryText)
            .frame(width: 110)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var preview: some View {
        let layout = skin.portrait ?? skin.landscape
        switch skin.source {
        case .builtIn(let style):
            if let layout {
                BuiltInSkinArt(style: style, layout: BuiltInSkins.adapted(layout, keyboard: false),
                               pressed: [], held: [:])
                    .frame(width: 414, height: 896)
                    .scaleEffect(92 / 414)
                    .frame(width: 92, height: 199)
            }
        case .imported:
            if let url = layout?.artwork, let image = SkinArtwork.image(url, size: CGSize(width: 184, height: 398)) {
                Image(uiImage: image).resizable()
            } else {
                Theme.surface2
            }
        }
    }
}

/// The licenses of the code inside Ember.
private struct LicensesView: View {
    private struct Entry: Identifiable, Decodable {
        var id: String { name }
        let name: String
        let license: String
        let text: String?
    }

    private var entries: [Entry] {
        var list = [
            Entry(name: String(localized: "Ember"), license: "GPL-3.0", text: nil),
            Entry(name: String(localized: "ZIPFoundation"), license: "MIT", text: nil),
            Entry(name: String(localized: "libarchive (iOS)"), license: "BSD-2-Clause",
                  text: Bundle.main.url(forResource: "libarchive-COPYING", withExtension: "txt")
                      .flatMap { try? String(contentsOf: $0, encoding: .utf8) }),
        ]
        if let url = Bundle.main.url(forResource: "EngineLicenses", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let engine = try? JSONDecoder().decode([Entry].self, from: data) {
            list += engine
        }
        return list
    }

    var body: some View {
        List(entries) { entry in
            if let text = entry.text, !text.isEmpty {
                NavigationLink {
                    ScrollView {
                        Text(text)
                            .font(.footnote.monospaced())
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .navigationTitle(entry.name)
                } label: {
                    LabeledContent(entry.name, value: entry.license)
                }
            } else {
                LabeledContent(entry.name, value: entry.license)
            }
        }
        .navigationTitle("Licenças")
    }
}
