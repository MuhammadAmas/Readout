import Combine
import Foundation

@MainActor
public final class ReadingQueue: ObservableObject {
    public enum State: Equatable {
        case idle
        case speaking
        case paused
    }

    @Published public private(set) var state: State = .idle
    @Published public private(set) var sentences: [String] = []
    @Published public private(set) var currentIndex = 0
    @Published public private(set) var spokenRange: NSRange?

    public var onFinish: (() -> Void)?
    public let lookahead: Int

    private let engine: any SpeechEngine
    private var settings = SpeechVoiceSettings()
    private var pending: [SpeechRequest] = []
    private var nextIndex = 0
    private var nextRequestID = 0
    private var settingsChangedWhilePaused = false

    public init(engine: any SpeechEngine, lookahead: Int = 2) {
        self.engine = engine
        self.lookahead = max(1, lookahead)
        engine.delegate = self
    }

    public var isActive: Bool { state != .idle }

    public var currentSentence: String? {
        sentences.indices.contains(currentIndex) ? sentences[currentIndex] : nil
    }

    public var currentSettings: SpeechVoiceSettings { settings }

    public func start(_ newSentences: [String], settings newSettings: SpeechVoiceSettings) {
        let content = newSentences.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !content.isEmpty else {
            stop()
            return
        }
        sentences = content
        settings = newSettings
        play(from: 0)
    }

    public func stop() {
        guard state != .idle else { return }
        engine.stop()
        finish()
    }

    public func togglePause() {
        switch state {
        case .speaking: pause()
        case .paused: resume()
        case .idle: break
        }
    }

    public func pause() {
        guard state == .speaking else { return }
        engine.pause()
        state = .paused
    }

    public func resume() {
        guard state == .paused else { return }
        if settingsChangedWhilePaused {
            play(from: currentIndex)
        } else {
            engine.resume()
            state = .speaking
        }
    }

    public func skip(by offset: Int) {
        guard state != .idle else { return }
        let target = currentIndex + offset
        if target >= sentences.count {
            stop()
            return
        }
        play(from: max(0, target))
    }

    public func jump(to index: Int) {
        guard state != .idle, sentences.indices.contains(index) else { return }
        play(from: index)
    }

    public func update(settings newSettings: SpeechVoiceSettings) {
        guard newSettings != settings else { return }
        settings = newSettings
        switch state {
        case .speaking: play(from: currentIndex)
        case .paused: settingsChangedWhilePaused = true
        case .idle: break
        }
    }

    private func play(from index: Int) {
        engine.stop()
        pending.removeAll()
        settingsChangedWhilePaused = false
        currentIndex = index
        nextIndex = index
        spokenRange = nil
        state = .speaking
        fill()
    }

    private func fill() {
        while pending.count < lookahead, nextIndex < sentences.count {
            let request = SpeechRequest(
                id: nextRequestID,
                sentenceIndex: nextIndex,
                text: sentences[nextIndex],
                settings: settings
            )
            nextRequestID += 1
            nextIndex += 1
            pending.append(request)
            engine.speak(request)
        }
    }

    private func finish() {
        pending.removeAll()
        state = .idle
        sentences = []
        currentIndex = 0
        nextIndex = 0
        spokenRange = nil
        settingsChangedWhilePaused = false
        onFinish?()
    }
}

extension ReadingQueue: SpeechEngineDelegate {
    public func speechEngine(_ engine: any SpeechEngine, didStart request: SpeechRequest) {
        guard pending.contains(where: { $0.id == request.id }) else { return }
        currentIndex = request.sentenceIndex
        spokenRange = nil
    }

    public func speechEngine(_ engine: any SpeechEngine, willSpeak range: NSRange, of request: SpeechRequest) {
        guard request.sentenceIndex == currentIndex,
              pending.contains(where: { $0.id == request.id })
        else { return }
        spokenRange = range
    }

    public func speechEngine(_ engine: any SpeechEngine, didFinish request: SpeechRequest) {
        guard let position = pending.firstIndex(where: { $0.id == request.id }) else { return }
        pending.remove(at: position)
        if pending.isEmpty, nextIndex >= sentences.count {
            finish()
        } else {
            fill()
        }
    }
}
