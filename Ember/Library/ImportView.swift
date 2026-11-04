import SwiftUI
import UniformTypeIdentifiers

/// The ways to bring a game into Ember, as in Manic EMU's import screen.
struct ImportView: View {
    @ObservedObject private var library = LibraryStore.shared
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Traga jogos de RPG Maker XP, VX ou VX Ace: .zip, .rar, .7z ou a pasta do jogo. O Ember encontra o jogo mesmo dentro de subpastas e, se você quiser, apaga o arquivo compactado depois para liberar espaço.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.horizontal, 4)

                    ImportOption(
                        icon: "folder.fill",
                        title: "Arquivos",
                        text: "Escolha no app Arquivos, no iCloud Drive ou em outro serviço instalado.") {
                        Button {
                            showingPicker = true
                        } label: {
                            Label("Escolher no Arquivos", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accent)
                        .controlSize(.large)
                    }

                    ImportOption(
                        icon: "laptopcomputer.and.iphone",
                        title: "Pelo Mac",
                        text: "Sem cabo de rede nem app extra: o Finder copia direto para o Ember.") {
                        VStack(alignment: .leading, spacing: 10) {
                            Step(number: 1, text: "Conecte o iPhone ao Mac com o cabo. Depois da primeira vez, o mesmo Wi-Fi basta.")
                            Step(number: 2, text: "No Finder, escolha o iPhone na barra lateral e abra a aba Arquivos.")
                            Step(number: 3, text: "Arraste o .zip, .rar, .7z ou a pasta do jogo para o Ember.")
                            Step(number: 4, text: "Abra o Ember. O jogo aparece na Biblioteca.")
                        }
                    }

                    ImportOption(
                        icon: "square.and.arrow.up",
                        title: "De outro app",
                        text: "No Safari, no Arquivos ou num app de mensagens, toque no arquivo, depois em Compartilhar e em Ember. Skins (.deltaskin, .manicskin) chegam do mesmo jeito.") {
                        EmptyView()
                    }
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Importar")
        }
        .fileImporter(isPresented: $showingPicker,
                      allowedContentTypes: UTType.importable,
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            library.importItems(urls)
            // The progress shows on the library.
            AppRouter.shared.tab = .library
        }
    }
}

private struct ImportOption<Content: View>: View {
    let icon: String
    let title: String
    let text: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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

extension UTType {
    static let rar = UTType(importedAs: "com.rarlab.rar-archive")
    static let sevenZip = UTType(importedAs: "org.7-zip.7-zip-archive")
    static let deltaSkin = UTType(importedAs: "com.rileytestut.delta.skin")
    static let manicSkin = UTType(importedAs: "com.alexandrethadeu.ember.manicskin")

    /// What the game importer takes.
    static let importable: [UTType] = [.zip, .rar, .sevenZip, .folder]
    /// What the skin importer takes.
    static let skins: [UTType] = [.deltaSkin, .manicSkin, .zip, .folder]
}
