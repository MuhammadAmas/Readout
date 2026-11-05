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
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.title = "Welcome to Readout"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

struct OnboardingView: View {
    static let sample = "Readout turns any text you select into speech, right here on your Mac, without sending a word anywhere."

    @ObservedObject var model: AppModel
    let onDone: () -> Void

    @State private var showsStaleHint = false

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            if model.isTrusted {
                ready
            } else {
                permission
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 34)
        .padding(.bottom, 26)
        .frame(width: 480)
        .animation(.smooth(duration: 0.3), value: model.isTrusted)
    }

    private var permission: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("Welcome to Readout")
                    .font(.title.weight(.semibold))
                Text("Select text in any app, press \(Hotkeys.label(for: .readSelection)), and hear it read aloud.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("Allow Accessibility access").font(.headline)
                } icon: {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.tint)
                }
                Text("Readout needs it to see the text you select. In browsers and some other apps it copies the selection for a moment, then puts your clipboard back exactly as it was.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Click Open Accessibility Settings.")
                    step(2, "Turn on Readout. This window updates by itself.")
                }
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for access…").foregroundStyle(.secondary)
                }
                .font(.callout)
                if showsStaleHint {
                    Text("Readout already on? Select it, remove it with −, and turn it on again. macOS treats an updated copy as a new app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Button("Not Now", action: onDone)
                    .controlSize(.large)
                Spacer()
                Button("Open Accessibility Settings") {
                    AccessibilityPermission.requestPrompt()
                    AccessibilityPermission.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            withAnimation { showsStaleHint = true }
        }
    }

    private var ready: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("You're all set")
                    .font(.title.weight(.semibold))
                Text("Try it now: select the sentence below and press \(Hotkeys.label(for: .readSelection)).")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(Self.sample)
                .font(.system(size: 15))
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)

            Text("Press \(Hotkeys.label(for: .readSelection)) again to stop and \(Hotkeys.label(for: .pauseResume)) to pause. Shortcuts, voices and speed are in Settings.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Read It to Me") { model.read(Self.sample) }
                    .controlSize(.large)
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .transition(.opacity)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(.tint))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
