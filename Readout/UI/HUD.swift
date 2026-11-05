import AppKit
import SwiftUI

@MainActor
final class HUDController {
    private var panel: FloatingPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, symbol: String) {
        let hosting = NSHostingView(rootView: HUDView(message: message, symbol: symbol))
        let size = hosting.fittingSize
        let panel = self.panel ?? FloatingPanel(size: size, interactive: false)
        self.panel = panel
        panel.contentView = hosting

        if let screen = NSScreen.withMouse {
            let frame = screen.visibleFrame
            let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - frame.height * 0.22 - size.height / 2)
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
        }

        hideTask?.cancel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        hideTask = Task { [weak self, weak panel] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled, let panel else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
            self?.hideTask = nil
        }
    }
}

struct HUDView: View {
    let message: String
    let symbol: String

    var body: some View {
        Label(message, systemImage: symbol)
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .floatingSurface(cornerRadius: 24)
            .padding(12)
            .accessibilityElement(children: .combine)
    }
}
