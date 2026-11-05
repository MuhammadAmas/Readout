import AppKit
import AVFoundation
import Combine
import ReadoutCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let queue: ReadingQueue
    let previewQueue: ReadingQueue
    let hud = HUDController()
    private(set) lazy var miniPlayer = MiniPlayerController(model: self)

    @Published private(set) var isTrusted = AccessibilityPermission.isTrusted
    @Published private(set) var isCapturing = false
    @Published private(set) var lastCaptureSource: SelectionReader.Source?

    private let readingEngine = RoutingSpeechEngine()
    private let previewEngine = RoutingSpeechEngine()
    private var trustTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        queue = ReadingQueue(engine: readingEngine)
        previewQueue = ReadingQueue(engine: previewEngine, lookahead: 1)
        queue.onFinish = { [weak self] in
            self?.miniPlayer.hide()
        }
        queue.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        previewQueue.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.applyLiveSettings() }
            .store(in: &cancellables)
        watchTrust()
        prepareVoice()
    }

    func prepareVoice() {
        readingEngine.prepare(voiceIdentifier: voiceSettings(for: "", matchLanguage: false).voiceIdentifier)
    }

    func toggleReading() {
        Log.capture.info("Read hotkey pressed (reading: \(self.queue.isActive, privacy: .public), capturing: \(self.isCapturing, privacy: .public))")
        if queue.isActive {
            queue.stop()
            return
        }
        guard !isCapturing else { return }
        prepareVoice()
        Task { await readSelection() }
    }

    func readSelectionFromMenu() {
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            await readSelection()
        }
    }

    func togglePause() {
        queue.togglePause()
    }

    func stop() {
        queue.stop()
    }

    func skip(by offset: Int) {
        queue.skip(by: offset)
    }

    func setRate(_ rate: Double) {
        UserDefaults.standard.set(rate, forKey: Preferences.speechRate)
        applyLiveSettings()
    }

    func hideMiniPlayer() {
        miniPlayer.hide()
    }

    func read(_ text: String) {
        previewQueue.stop()
        let cleaned = TextCleaner.clean(text, options: Preferences.cleanupOptions)
        let sentences = SentenceSplitter.split(cleaned)
        guard !sentences.isEmpty else {
            hud.show("Nothing to read", symbol: "text.badge.xmark")
            return
        }
        let settings = voiceSettings(for: cleaned)
        Log.speech.info("Reading \(sentences.count, privacy: .public) sentences with voice \(settings.voiceIdentifier ?? "default", privacy: .public)")
        queue.start(sentences, settings: settings)
        if UserDefaults.standard.bool(forKey: Preferences.showMiniPlayer) {
            miniPlayer.show()
        }
    }

    func togglePreview() {
        if previewQueue.isActive {
            previewQueue.stop()
            return
        }
        queue.stop()
        let sample = "This is how Readout sounds at this speed. Select text anywhere and press the shortcut to hear it."
        previewQueue.start(SentenceSplitter.split(sample), settings: voiceSettings(for: sample, matchLanguage: false))
    }

    func showOnboarding() {
        OnboardingWindowController.shared.show(model: self)
    }

    func showSettings() {
        SettingsWindowController.shared.show(model: self)
    }

    func refreshTrust() {
        let trusted = AccessibilityPermission.isTrusted
        if trusted != isTrusted {
            isTrusted = trusted
        }
        if !trusted {
            watchTrust()
        }
    }

    func voiceSettings(for text: String, matchLanguage: Bool? = nil) -> SpeechVoiceSettings {
        let defaults = UserDefaults.standard
        let chosen = defaults.string(forKey: Preferences.voiceIdentifier).flatMap { $0.isEmpty ? nil : $0 }
        let chosenVoice = chosen.flatMap(VoiceCatalog.option(identifier:))
        let chosenLanguage = chosenVoice?.language ?? AVSpeechSynthesisVoice.currentLanguageCode()
        var identifier = chosenVoice?.id ?? VoiceCatalog.bestVoice(forLanguage: chosenLanguage)?.id

        if matchLanguage ?? defaults.bool(forKey: Preferences.matchTextLanguage),
           let language = LanguageDetector.dominantLanguage(of: text),
           !LanguageDetector.isSameLanguage(language, chosenLanguage),
           let match = VoiceCatalog.bestVoice(forLanguage: language) {
            identifier = match.id
        }
        return SpeechVoiceSettings(voiceIdentifier: identifier, rateMultiplier: Preferences.rate)
    }

    private func readSelection() async {
        refreshTrust()
        Log.capture.info("Accessibility trusted: \(self.isTrusted, privacy: .public)")
        guard isTrusted else {
            showOnboarding()
            return
        }
        isCapturing = true
        defer { isCapturing = false }
        guard let capture = await SelectionReader.capture() else {
            Log.capture.info("Nothing captured")
            hud.show("Nothing selected", symbol: "text.badge.xmark")
            return
        }
        lastCaptureSource = capture.source
        read(capture.text)
    }

    private func applyLiveSettings() {
        for active in [queue, previewQueue] where active.isActive {
            var settings = active.currentSettings
            settings.rateMultiplier = Preferences.rate
            active.update(settings: SpeechVoiceSettings(
                voiceIdentifier: settings.voiceIdentifier,
                rateMultiplier: settings.rateMultiplier,
                volume: settings.volume
            ))
        }
    }

    private func watchTrust() {
        guard trustTimer == nil, !isTrusted else { return }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else {
                    timer.invalidate()
                    return
                }
                if AccessibilityPermission.isTrusted {
                    self.isTrusted = true
                    timer.invalidate()
                    self.trustTimer = nil
                }
            }
        }
    }
}
