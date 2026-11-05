import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    func show(model: AppModel) {
        let window = self.window ?? makeWindow(model: model)
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func makeWindow(model: AppModel) -> NSWindow {
        let view = OnboardingView(model: model) { [weak self] in
            UserDefaults.standard.set(true, forKey: Preferences.hasCompletedOnboarding)
            self?.close()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Readout"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        return window
    }
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("Readout reads selected text aloud")
                    .font(.title2.weight(.semibold))
                Text("Select text in any app and press \(Hotkeys.label(for: .readSelection)). Press it again to stop, or \(Hotkeys.label(for: .pauseResume)) to pause.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Readout needs Accessibility access", systemImage: "hand.raised.fill")
                    .font(.headline)
                Text("macOS only lets an app see what you've selected in another app if you allow it. Where an app doesn't share its selection (most browsers and Electron apps), Readout presses ⌘C for you, then puts your clipboard back exactly as it was.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Everything stays on this Mac. Readout makes no network requests.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 4) {
                    step(1, "Click Open Accessibility Settings.")
                    step(2, "Turn on Readout in the list. Unlock with your password if asked. If it's already on and this window still waits, select Readout, remove it with −, then click Open Accessibility Settings again. A rebuilt copy counts as a new app.")
                    step(3, "Come back here. This window notices on its own.")
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            status

            HStack {
                if model.isTrusted {
                    Button("Start Using Readout", action: onDone)
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                } else {
                    Button("Later", action: onDone)
                        .controlSize(.large)
                    Button("Open Accessibility Settings") {
                        AccessibilityPermission.requestPrompt()
                        AccessibilityPermission.openSystemSettings()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding(28)
        .frame(width: 520)
    }

    private var status: some View {
        HStack(spacing: 8) {
            if model.isTrusted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Access granted. You're ready.")
            } else {
                ProgressView().controlSize(.small)
                Text("Waiting for permission…").foregroundStyle(.secondary)
            }
        }
        .font(.callout.weight(.medium))
        .animation(.default, value: model.isTrusted)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
