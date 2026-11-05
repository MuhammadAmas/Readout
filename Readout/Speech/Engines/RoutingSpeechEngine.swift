import Foundation
import ReadoutCore

@MainActor
final class RoutingSpeechEngine: SpeechEngine, SpeechEngineDelegate {
    weak var delegate: (any SpeechEngineDelegate)?

    private let system = SystemSpeechEngine()
    private var neural: NeuralSpeechEngine?

    init() {
        system.delegate = self
    }

    func prepare(voiceIdentifier: String?) {
        guard let voice = voiceIdentifier.flatMap(KokoroVoice.voice(identifier:)),
              NeuralVoiceInstallation.isInstalled
        else { return }
        neuralEngine().prepare(voice)
    }

    func speak(_ request: SpeechRequest) {
        if let identifier = request.settings.voiceIdentifier,
           KokoroVoice.voice(identifier: identifier) != nil,
           NeuralVoiceInstallation.isInstalled {
            neuralEngine().speak(request)
        } else {
            system.speak(request)
        }
    }

    func pause() {
        system.pause()
        neural?.pause()
    }

    func resume() {
        system.resume()
        neural?.resume()
    }

    func stop() {
        system.stop()
        neural?.stop()
    }

    func speechEngine(_ engine: any SpeechEngine, didStart request: SpeechRequest) {
        delegate?.speechEngine(self, didStart: request)
    }

    func speechEngine(_ engine: any SpeechEngine, willSpeak range: NSRange, of request: SpeechRequest) {
        delegate?.speechEngine(self, willSpeak: range, of: request)
    }

    func speechEngine(_ engine: any SpeechEngine, didFinish request: SpeechRequest) {
        delegate?.speechEngine(self, didFinish: request)
    }

    private func neuralEngine() -> NeuralSpeechEngine {
        if let neural { return neural }
        let engine = NeuralSpeechEngine()
        engine.delegate = self
        neural = engine
        return engine
    }
}
