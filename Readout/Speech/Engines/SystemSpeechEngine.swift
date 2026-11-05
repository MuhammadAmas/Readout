import AVFoundation
import ReadoutCore

@MainActor
final class SystemSpeechEngine: NSObject, SpeechEngine {
    weak var delegate: (any SpeechEngineDelegate)?

    private var synthesizer = AVSpeechSynthesizer()
    private var requests: [ObjectIdentifier: (utterance: AVSpeechUtterance, request: SpeechRequest)] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    func speak(_ request: SpeechRequest) {
        let utterance = AVSpeechUtterance(string: request.text)
        utterance.voice = request.settings.voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
        utterance.rate = Self.rate(for: request.settings.rateMultiplier)
        utterance.volume = request.settings.volume
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        utterance.prefersAssistiveTechnologySettings = false
        requests[ObjectIdentifier(utterance)] = (utterance, request)
        synthesizer.speak(utterance)
    }

    func pause() {
        synthesizer.pauseSpeaking(at: .immediate)
    }

    func resume() {
        synthesizer.continueSpeaking()
    }

    func stop() {
        guard synthesizer.isSpeaking || synthesizer.isPaused || !requests.isEmpty else { return }
        let previous = synthesizer
        previous.delegate = nil
        previous.stopSpeaking(at: .immediate)
        requests.removeAll()
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
    }

    static func rate(for multiplier: Double) -> Float {
        let clamped = Float(min(max(multiplier, SpeechVoiceSettings.rateRange.lowerBound), SpeechVoiceSettings.rateRange.upperBound))
        let normal = AVSpeechUtteranceDefaultSpeechRate
        if clamped >= 1 {
            return normal + (AVSpeechUtteranceMaximumSpeechRate - normal) * (clamped - 1)
        }
        return normal - (normal - AVSpeechUtteranceMinimumSpeechRate) * (1 - clamped)
    }

    private enum Event {
        case start
        case word(NSRange)
        case finish
        case cancel
    }

    private func handle(_ event: Event, utterance key: ObjectIdentifier, synthesizer source: ObjectIdentifier) {
        guard source == ObjectIdentifier(synthesizer), let entry = requests[key] else { return }
        switch event {
        case .start:
            delegate?.speechEngine(self, didStart: entry.request)
        case .word(let range):
            delegate?.speechEngine(self, willSpeak: range, of: entry.request)
        case .finish:
            requests[key] = nil
            delegate?.speechEngine(self, didFinish: entry.request)
        case .cancel:
            requests[key] = nil
        }
    }

    private nonisolated func deliver(_ event: Event, _ utterance: AVSpeechUtterance, _ synthesizer: AVSpeechSynthesizer) {
        let key = ObjectIdentifier(utterance)
        let source = ObjectIdentifier(synthesizer)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.handle(event, utterance: key, synthesizer: source)
            }
        }
    }
}

extension SystemSpeechEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        deliver(.start, utterance, synthesizer)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        deliver(.word(characterRange), utterance, synthesizer)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        deliver(.finish, utterance, synthesizer)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        deliver(.cancel, utterance, synthesizer)
    }
}
