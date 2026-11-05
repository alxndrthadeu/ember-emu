import Photos
import SwiftUI
import UIKit

/// Settings that outlive a game session.
enum GameSettings {
    static let speedSteps = [1, 2, 3, 5]

    static var speed: Int {
        get { max(1, UserDefaults.standard.integer(forKey: "game.speed")) }
        set { UserDefaults.standard.set(newValue, forKey: "game.speed") }
    }

    /// Pushes the saved settings into the engine.
    static func apply() {
        mkxp_setFastForwardMultiplier(Int32(speed))
    }
}

/// The in-game menu behind the gear: a grid of tiles over the paused
/// game, as in Manic EMU.
struct GameMenuView: View {
    let title: String
    /// Run after the menu closed and the game resumed.
    var onSaveState: () -> Void = {}
    var onShowStates: () -> Void = {}
    /// Ends the game. The caller dismisses the menu first.
    let onQuit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var pause = PauseSnapshot.shared
    @ObservedObject private var performance = PerformanceModel.shared
    @ObservedObject private var tv = TVStream.shared
    @State private var showingTV = false
    @ObservedObject private var skins = SkinStore.shared
    @ObservedObject private var audio = GameAudio.shared
    @State private var speed = GameSettings.speed
    @State private var confirmingQuit = false
    @State private var toast: String?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            EmberGlassContainer(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                MenuTile(icon: "forward.fill", title: String(localized: "Velocidade"),
                         value: String(localized: "\(speed)x"), highlighted: speed > 1) {
                    let steps = GameSettings.speedSteps
                    speed = steps[((steps.firstIndex(of: speed) ?? 0) + 1) % steps.count]
                    GameSettings.speed = speed
                    GameSettings.apply()
                }
                MenuTile(icon: "square.and.arrow.down.on.square.fill", title: String(localized: "Salvar estado")) {
                    dismiss()
                    onSaveState()
                }
                MenuTile(icon: "clock.arrow.trianglehead.counterclockwise.rotate.90", title: String(localized: "Estados")) {
                    dismiss()
                    onShowStates()
                }
                MenuTile(icon: "camera.fill", title: String(localized: "Captura")) {
                    saveScreenshot()
                }
                MenuTile(icon: skins.portraitFullWidth ? "rectangle.inset.filled" : "rectangle.center.inset.filled",
                         title: String(localized: "Tela"),
                         value: skins.portraitFullWidth ? String(localized: "Tela cheia") : String(localized: "Clássica")) {
                    skins.portraitFullWidth.toggle()
                }
                MenuTile(icon: audio.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                         title: String(localized: "Som"),
                         value: audio.soundOn ? String(localized: "Ligado") : String(localized: "Desligado"),
                         highlighted: !audio.soundOn) {
                    audio.soundOn.toggle()
                }
                MenuTile(icon: "gauge.with.dots.needle.67percent", title: String(localized: "Desempenho"),
                         value: performance.enabled ? String(localized: "Ligado") : String(localized: "Desligado"), highlighted: performance.enabled) {
                    performance.enabled.toggle()
                }
                MenuTile(icon: "keyboard", title: String(localized: "Teclado")) {
                    dismiss()
                    // After the sheet is gone, so the keyboard has a window.
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        EngineSession.shared.openKeyboard()
                    }
                }
                MenuTile(icon: tv.viewers > 0 ? "tv.fill" : "tv", title: String(localized: "TV"),
                         value: tv.viewers > 0 ? String(localized: "Na TV")
                             : (tv.isOn ? String(localized: "Ligada") : String(localized: "Desligada")),
                         highlighted: tv.isOn) {
                    showingTV = true
                }
                MenuTile(icon: "xmark.circle.fill", title: String(localized: "Sair"), destructive: true) {
                    confirmingQuit = true
                }
            }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showingTV) {
            TVSheet()
                .presentationDetents([.height(460)])
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .foregroundStyle(Theme.onHighlight)
                    .emberGlass(.regular.tint(Theme.highlight), in: Capsule())
                    .transition(.opacity)
                    .padding(.bottom, 12)
            }
        }
        .confirmationDialog("Sair de \(title)?", isPresented: $confirmingQuit, titleVisibility: .visible) {
            Button("Sair do jogo", role: .destructive) {
                dismiss()
                onQuit()
            }
        } message: {
            Text("O progresso que não foi salvo no jogo será perdido.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pausado")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .textCase(.uppercase)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .emberGlass(.regular.interactive(), in: Circle())
            .accessibilityLabel("Voltar ao jogo")
        }
    }

    private func saveScreenshot() {
        guard let image = pause.image else {
            show(String(localized: "A captura ainda não está pronta"))
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in show(String(localized: "Sem permissão para salvar em Fotos")) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            } completionHandler: { ok, _ in
                Task { @MainActor in show(ok ? String(localized: "Salvo em Fotos") : String(localized: "Não deu para salvar")) }
            }
        }
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { if toast == message { toast = nil } }
        }
    }
}

private struct MenuTile: View {
    let icon: String
    let title: String
    var value: String?
    var highlighted = false
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(foreground(destructive ? Theme.accent : Theme.primaryText))
                    .frame(height: 26)
                Text(value ?? title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(foreground(destructive ? Theme.accent : Theme.primaryText))
                if value != nil {
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(foreground(Theme.secondaryText))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .emberGlass(highlighted ? .regular.tint(Theme.highlight).interactive() : .regular.interactive(),
                     in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .buttonStyle(.plain)
    }

    /// Âmbar means "on": its text is always the dark ink.
    private func foreground(_ color: Color) -> Color {
        highlighted ? Theme.onHighlight : color
    }
}

/// The frame the engine captured when it paused, as a UIImage.
@MainActor
final class PauseSnapshot: ObservableObject {
    static let shared = PauseSnapshot()

    @Published private(set) var image: UIImage?

    private init() {}

    /// The engine fires the paused callback on its own thread, after
    /// it stored the frame.
    func observeEngine() {
        mkxp_setPausedCallback({ _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { PauseSnapshot.shared.capture() }
            }
        }, nil)
    }

    func clear() { image = nil }

    private func capture() {
        var width: Int32 = 0
        var height: Int32 = 0
        guard mkxp_getSnapshotSize(&width, &height), width > 0, height > 0 else { return }
        var pixels = [UInt8](repeating: 0, count: Int(width * height * 4))
        guard mkxp_copySnapshotRGBA(&pixels, Int32(pixels.count), &width, &height) else { return }

        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let cgImage = CGImage(width: Int(width), height: Int(height),
                                    bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: Int(width) * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                    provider: provider, decode: nil,
                                    shouldInterpolate: false, intent: .defaultIntent)
        else { return }
        image = UIImage(cgImage: cgImage)
        if let id = EngineSession.shared.currentGame?.id, let image {
            GameCovers.saveSnapshot(image, forGameID: id)
        }
    }
}
