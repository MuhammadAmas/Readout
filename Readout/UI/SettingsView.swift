import AppKit
import AVFoundation
import KeyboardShortcuts
import LaunchAtLogin
import ReadoutCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    enum Pane: String, CaseIterable {
        case general, voice, text

        var title: String {
            switch self {
            case .general: "General"
            case .voice: "Voice"
            case .text: "Text"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .voice: "waveform"
            case .text: "text.alignleft"
            }
        }

        @MainActor
        func content(model: AppModel) -> AnyView {
            switch self {
            case .general: AnyView(GeneralSettings(model: model).settingsPane())
            case .voice: AnyView(VoiceSettings(model: model).settingsPane())
            case .text: AnyView(TextSettings().settingsPane())
            }
        }
    }

    static let shared = SettingsWindowController()
    static let selectedPaneKey = "settingsTab"

    private var window: NSWindow?

    func show(model: AppModel) {
        let window = self.window ?? makeWindow(model: model)
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(model: AppModel) -> NSWindow {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true
        for pane in Pane.allCases {
            let controller = NSHostingController(rootView: pane.content(model: model))
            controller.sizingOptions = .preferredContentSize
            controller.title = pane.title
            let item = NSTabViewItem(viewController: controller)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            item.identifier = pane.rawValue
            tabs.addTabViewItem(item)
        }
        let saved = UserDefaults.standard.string(forKey: Self.selectedPaneKey)
        tabs.selectedTabViewItemIndex = Pane.allCases.firstIndex { $0.rawValue == saved } ?? 0

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let identifier = tabViewItem?.identifier as? String {
            UserDefaults.standard.set(identifier, forKey: SettingsWindowController.selectedPaneKey)
        }
    }
}

private extension View {
    func settingsPane() -> some View {
        formStyle(.grouped)
            .frame(width: 520)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @AppStorage(Preferences.showMiniPlayer) private var showMiniPlayer = Preferences.Defaults.showMiniPlayer
    @AppStorage(Preferences.automaticUpdates) private var automaticUpdates = Preferences.Defaults.automaticUpdates

    private var updateDetail: String {
        let version = "Version \(Updater.shared.currentVersion)."
        guard Updater.shared.canReplaceItself else {
            return "\(version) Only a copy installed in Applications can update itself."
        }
        return "\(version) New versions install by themselves when Readout isn't reading."
    }

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Read or stop") {
                    ShortcutRecorder(name: .readSelection, others: [.pauseResume])
                }
                LabeledContent("Pause or resume") {
                    ShortcutRecorder(name: .pauseResume, others: [.readSelection])
                }
            }

            Section {
                Toggle("Show mini player while reading", isOn: $showMiniPlayer)
                LaunchAtLogin.Toggle("Open at login")
                Toggle(isOn: $automaticUpdates) {
                    Text("Update automatically")
                    Text(updateDetail)
                }
            }

            Section {
                HStack(spacing: 10) {
                    Image(systemName: model.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(model.isTrusted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.isTrusted ? "Accessibility access allowed" : "Accessibility access needed")
                        Text(model.isTrusted ? "Readout can read text you select in other apps." : "Without it, Readout can't see what you've selected.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !model.isTrusted {
                        Button("Open Settings") {
                            AccessibilityPermission.requestPrompt()
                            AccessibilityPermission.openSystemSettings()
                        }
                    }
                }
            } footer: {
                Text("Everything Readout reads stays on this Mac. Its only network request is a check of GitHub for a new version, which sends nothing about you or what you read. No analytics.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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

            Section {
                if NeuralVoiceInstallation.isInstalled {
                    LabeledContent {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } label: {
                        Text("Neural voices")
                        Text("\(KokoroVoice.all.count) natural English voices from Kokoro, made on this Mac. They take about half a second longer to start.")
                    }
                } else {
                    LabeledContent {
                        Button("Copy Command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(NeuralVoiceInstallation.installCommand, forType: .string)
                        }
                    } label: {
                        Text("Neural voices")
                        Text("Add 27 very natural English voices that run offline (a one-time 360 MB download). Paste the command into Terminal, then reopen Settings.")
                    }
                }
                LabeledContent {
                    Button("Open Spoken Content") {
                        AccessibilityPermission.openSpokenContentSettings()
                    }
                } label: {
                    Text("System voices")
                    Text("Download Premium or Enhanced voices under Spoken Content › Manage Voices. ★ marks languages that have one.")
                }
            } header: {
                Text("More voices")
            }
        }
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
    @AppStorage(Preferences.technicalSpeech) private var technicalSpeech = Preferences.Defaults.technicalSpeech
    @AppStorage(Preferences.codeBlockMode) private var codeBlockMode = Preferences.Defaults.codeBlockMode
    @State private var pronunciations: [EditablePronunciation] = Preferences.savedPronunciations.map(EditablePronunciation.init)
    @State private var sample = """
    ## Deploy notes
    Run `npm run build --prod`, then check `user_id != nil` in src/app/main.ts (see issue #4512).

    | Service | Status |
    |---------|--------|
    | OpenTelemetry | Live |

    ```swift
    let user = try await api.fetchUser(id: userID)
    ```
    """

    var body: some View {
        Form {
            Section("Clean-up before speaking") {
                Toggle(isOn: $cleanupEnabled) {
                    Text("Clean up Markdown, links and symbols")
                    Text("Removes Markdown symbols, reads tables as \u{201C}column: value\u{201D}, shortens links to their domain, and says & as \u{201C}and\u{201D} and e.g. as \u{201C}for example\u{201D}.")
                }
                Toggle(isOn: $technicalSpeech) {
                    Text("Make code and technical terms speakable")
                    Text("Reads getUserName() as \u{201C}get user name\u{201D}, --force as \u{201C}dash dash force\u{201D}, != as \u{201C}not equal to\u{201D}, main.ts as \u{201C}main dot T S\u{201D}, and terms like JSON, nginx and C# the way people say them.")
                }
                .disabled(!cleanupEnabled)
                Picker(selection: $codeBlockMode) {
                    Text("Skip, saying \u{201C}Code block skipped\u{201D}").tag(CodeBlockMode.skip.rawValue)
                    Text("Skip, saying its language and length").tag(CodeBlockMode.describe.rawValue)
                    Text("Read the code aloud").tag(CodeBlockMode.read.rawValue)
                } label: {
                    Text("Code blocks")
                }
                .disabled(!cleanupEnabled)
            }

            Section {
                ForEach($pronunciations) { $entry in
                    HStack(spacing: 8) {
                        TextField("Written", text: $entry.written)
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField("Say as", text: $entry.spoken)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            pronunciations.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                        .accessibilityLabel("Remove \(entry.written)")
                    }
                }
                Button("Add Pronunciation") {
                    pronunciations.append(EditablePronunciation(Pronunciation(written: "", spoken: "")))
                }
            } header: {
                Text("Pronunciations")
            } footer: {
                Text("Teach Readout names and terms it gets wrong, such as a product or a colleague's name. Matching ignores capitals and only replaces whole words.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(!cleanupEnabled)

            Section("Try it") {
                TextEditor(text: $sample)
                    .font(.system(.callout, design: .monospaced))
                    .frame(height: 160)
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
        .onChange(of: pronunciations) { _, entries in
            Preferences.save(pronunciations: entries.map(\.value))
        }
    }

    private var spoken: String {
        let options = CleanupOptions(
            isEnabled: cleanupEnabled,
            codeBlocks: CodeBlockMode(rawValue: codeBlockMode) ?? .skip,
            speaksTechnicalTerms: technicalSpeech,
            pronunciations: pronunciations.map(\.value)
        )
        return SentenceSplitter.split(TextCleaner.clean(sample, options: options)).joined(separator: " ")
    }
}

private struct EditablePronunciation: Identifiable, Equatable {
    let id = UUID()
    var written: String
    var spoken: String

    init(_ pronunciation: Pronunciation) {
        written = pronunciation.written
        spoken = pronunciation.spoken
    }

    var value: Pronunciation { Pronunciation(written: written, spoken: spoken) }
}
