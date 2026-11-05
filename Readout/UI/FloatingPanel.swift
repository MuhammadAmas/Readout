import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    init(size: NSSize, interactive: Bool) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = interactive ? .floating : .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = interactive
        ignoresMouseEvents = !interactive
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        animationBehavior = .utilityWindow
        if interactive {
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: self,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.settleAfterMove() }
            }
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.moveOnScreen(animated: true) }
            }
        }
    }

    deinit {
        [moveObserver, screenObserver].compactMap { $0 }.forEach(NotificationCenter.default.removeObserver)
    }

    var transparentMargin: CGFloat = 0
    static let edgeGap: CGFloat = 8

    private var moveObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var settleWork: DispatchWorkItem?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func moveOnScreen(animated: Bool) {
        guard let screen = bestScreen else { return }
        let inset = Self.edgeGap - transparentMargin
        let allowed = screen.visibleFrame.insetBy(dx: inset, dy: inset)
        var target = frame
        target.origin.x = min(max(target.minX, allowed.minX), allowed.maxX - target.width)
        target.origin.y = min(max(target.minY, allowed.minY), allowed.maxY - target.height)
        guard target.origin != frame.origin else { return }
        setFrame(target, display: true, animate: animated && isVisible)
    }

    private var bestScreen: NSScreen? {
        let overlap = { (screen: NSScreen) -> CGFloat in
            let shared = screen.frame.intersection(self.frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        if let screen = NSScreen.screens.max(by: { overlap($0) < overlap($1) }), overlap(screen) > 0 {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func settleAfterMove() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if NSEvent.pressedMouseButtons != 0 {
                    self.settleAfterMove()
                } else {
                    self.moveOnScreen(animated: true)
                }
            }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}

struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension NSScreen {
    static var withMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

extension View {
    @ViewBuilder
    func floatingSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(VisualEffectBackground().clipShape(shape))
                .overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        }
    }
}
