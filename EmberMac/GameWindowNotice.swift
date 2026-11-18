import AppKit
import SwiftUI

/// A short message over the top of the game's window ("Save no iCloud"),
/// for a few seconds. A borderless child window: SDL draws the game's
/// window itself, so nothing can go inside it.
@MainActor
enum GameWindowNotice {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ text: String, on window: NSWindow) {
        hideTask?.cancel()
        if let old = panel {
            old.parent?.removeChildWindow(old)
            old.orderOut(nil)
        }

        let host = NSHostingView(rootView: SyncToast(text: text).fixedSize().padding(4)
            // Over the game, which is always dark.
            .environment(\.colorScheme, .dark))
        let size = host.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        let content = window.contentRect(forFrameRect: window.frame)
        panel.setFrameOrigin(NSPoint(x: content.midX - size.width / 2, y: content.maxY - size.height - 12))
        panel.alphaValue = 0
        window.addChildWindow(panel, ordered: .above)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        Self.panel = panel

        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            NSAnimationContext.runAnimationGroup { $0.duration = 0.3; panel.animator().alphaValue = 0 } completionHandler: {
                MainActor.assumeIsolated {
                    window.removeChildWindow(panel)
                    panel.orderOut(nil)
                    if Self.panel === panel { Self.panel = nil }
                }
            }
        }
    }
}
