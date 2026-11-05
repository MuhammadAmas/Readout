import AppKit
import AVFoundation
import KeyboardShortcuts
import LaunchAtLogin
import ReadoutCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(model: AppModel) {
        let window = self.window ?? makeWindow(model: model)
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(model: AppModel) -> NSWindow {
        let hosting = NSHostingView(rootView: SettingsView(model: model))
        hosting.sizingOptions = [.intrinsicContentSize]
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Readout Settings"
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.center()
        window.setFrameAutosaveName("ReadoutSettings")
        return window
    }
}

struct SettingsView: View {
    enum Tab: String {
        case general, voice, text
    }

    @ObservedObject var model: AppModel
    @AppStorage("settingsTab") private var tab = Tab.general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(Tab.general)
            VoiceSettings(model: model)
                .tabItem { Label("Voice", systemImage: "waveform") }
                .tag(Tab.voice)
            TextSettings()
                .tabItem { Label("Text", systemImage: "text.alignleft") }
                .tag(Tab.text)
        }
        .padding(.top, 8)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @AppStorage(Preferences.showMiniPlayer) private var showMiniPlayer = Preferences.Defaults.showMiniPlayer

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Read selection / stop") {
                    ShortcutRecorder(name: .readSelection, others: [.pauseResume])
                }
                LabeledContent("Pause / resume") {
                    ShortcutRecorder(name: .pauseResume, others: [.readSelection])
                }
            }

            Section("Behaviour") {
                LaunchAtLogin.Toggle("Launch at login")
                Toggle("Show the mini player while reading", isOn: $showMiniPlayer)
            }

            Section("Accessibility access") {
                HStack {
                    if model.isTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not granted", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Open Accessibility Settings") {
                        AccessibilityPermission.requestPrompt()
                        AccessibilityPermission.openSystemSettings()
                    }
                }
            }

            Section {
                Text("Readout runs entirely on this Mac. It makes no network requests, collects no analytics, and never stores what it reads.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: model.refreshTrust)
    }
}

private struct VoiceSettings: View {
    private static let automatic = ""

    @ObservedObject var model: AppModel
    @AppStorage(Preferences.voiceIdentifier) private var voiceIdentifier = Preferences.Defaults.voiceIdentifier
    @AppStorage(Preferences.speechRate) private var rate = Preferences.Defaults.speechRate
    @AppStorage(Preferences.matchTextLanguage) private var matchTextLanguage = Preferences.Defaults.matchTextLanguage
    @State private var groups: [LanguageGroup] = []
    @State private var language = ""

    var body: some View {
        Form {
            Section("Voice") {
                Picker("Language", selection: $language) {
                    Text("Automatic").tag(Self.automatic)
                    Divider()
                    ForEach(groups) { group in
                        Text(group.hasHighQualityVoice ? "\(group.title) ★" : group.title).tag(group.id)
                    }
                }
                .onChange(of: language) { _, newValue in
                    selectBestVoice(in: newValue)
                }

                if let group = groups.first(where: { $0.id == language }) {
                    Picker("Voice", selection: $voiceIdentifier) {
                        ForEach(group.voices) { voice in
                            Text(voice.label).tag(voice.id)
                        }
                    }
                } else {
                    LabeledContent("Voice") {
                        Text(automaticVoiceName).foregroundStyle(.secondary)
                    }
                }

                Toggle("Switch voice when the text is in another language", isOn: $matchTextLanguage)
            }

            Section("Speed") {
                HStack(spacing: 12) {
                    Slider(value: $rate, in: SpeechVoiceSettings.rateRange, step: 0.05) {
                        Text("Speed")
                    } minimumValueLabel: {
                        Text("0.5×").font(.caption)
                    } maximumValueLabel: {
                        Text("2×").font(.caption)
                    }
                    .labelsHidden()
                    Text(Preferences.formatted(rate: rate))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                HStack {
                    Button(model.previewQueue.isActive ? "Stop Preview" : "Preview") {
                        model.togglePreview()
                    }
                    Button("Reset to 1×") { rate = 1 }
                        .disabled(abs(rate - 1) < 0.01)
                }
            }

            Section("Neural voices") {
                if NeuralVoiceInstallation.isInstalled {
                    Label("Kokoro is installed: \(KokoroVoice.all.count) natural-sounding English voices, generated on this Mac.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pick one under Language › English. The first sentence takes about half a second longer to start than a system voice. Text in other languages still uses the system voices.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Kokoro adds very natural English voices that run entirely on this Mac. Install them once by running \(NeuralVoiceInstallation.fetchScript) from the Readout folder (about 360 MB), then reopen this window.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Better system voices") {
                Text("Premium and Enhanced voices sound far more natural and work offline. Download them in System Settings › Accessibility › Spoken Content › System Voice › Manage Voices… They appear here as soon as they finish downloading. ★ marks languages that have one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Spoken Content Settings") {
                    AccessibilityPermission.openSpokenContentSettings()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            reload()
        }
    }

    private var automaticVoiceName: String {
        let settings = model.voiceSettings(for: "", matchLanguage: false)
        let name = settings.voiceIdentifier.flatMap(VoiceCatalog.option(identifier:))?.label ?? "System voice"
        return "Best installed: \(name)"
    }

    private func reload() {
        groups = VoiceCatalog.groups()
        if voiceIdentifier.isEmpty {
            language = Self.automatic
        } else if let group = groups.first(where: { $0.voices.contains { $0.id == voiceIdentifier } }) {
            language = group.id
        } else {
            voiceIdentifier = Self.automatic
            language = Self.automatic
        }
    }

    private func selectBestVoice(in language: String) {
        guard let group = groups.first(where: { $0.id == language }) else {
            voiceIdentifier = Self.automatic
            return
        }
        if !group.voices.contains(where: { $0.id == voiceIdentifier }) {
            voiceIdentifier = group.voices.first?.id ?? Self.automatic
        }
    }
}

private struct TextSettings: View {
    @AppStorage(Preferences.cleanupEnabled) private var cleanupEnabled = Preferences.Defaults.cleanupEnabled
    @AppStorage(Preferences.skipCodeBlocks) private var skipCodeBlocks = Preferences.Defaults.skipCodeBlocks
    @State private var sample = """
    ## Pricing
    | Plan | Price |
    |------|-------|
    | Pro  | $9    |

    See **https://example.com/pricing** & compare, e.g. yearly -> monthly.

    ```js
    console.log("hi")
    ```
    """

    var body: some View {
        Form {
            Section("Clean-up before speaking") {
                Toggle("Clean up Markdown, links and symbols", isOn: $cleanupEnabled)
                Toggle("Skip code blocks and say \u{201C}Code block skipped\u{201D}", isOn: $skipCodeBlocks)
                    .disabled(!cleanupEnabled)
                Text("Removes Markdown symbols (# * ` | >), reads tables as \u{201C}column: value\u{201D}, shortens links to their domain, and says & as \u{201C}and\u{201D}, -> as \u{201C}to\u{201D} and e.g. as \u{201C}for example\u{201D}.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Try it") {
                TextEditor(text: $sample)
                    .font(.system(.callout, design: .monospaced))
                    .frame(height: 130)
                    .scrollContentBackground(.hidden)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Readout will say:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(spoken.isEmpty ? "Nothing to read." : spoken)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var spoken: String {
        let options = CleanupOptions(isEnabled: cleanupEnabled, skipsCodeBlocks: skipCodeBlocks)
        return SentenceSplitter.split(TextCleaner.clean(sample, options: options)).joined(separator: " ")
    }
}
