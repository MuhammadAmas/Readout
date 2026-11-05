import Foundation
import Testing
@testable import ReadoutCore

@MainActor
final class FakeEngine: SpeechEngine {
    weak var delegate: (any SpeechEngineDelegate)?
    private(set) var spoken: [SpeechRequest] = []
    private(set) var stopCount = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var rateChanges: [Double] = []
    var changesRateLive = false

    func speak(_ request: SpeechRequest) { spoken.append(request) }
    func pause() { pauseCount += 1 }
    func resume() { resumeCount += 1 }
    func stop() { stopCount += 1 }

    func changeRate(to multiplier: Double) -> Bool {
        guard changesRateLive else { return false }
        rateChanges.append(multiplier)
        return true
    }

    func start(_ request: SpeechRequest) { delegate?.speechEngine(self, didStart: request) }
    func word(_ range: NSRange, in request: SpeechRequest) { delegate?.speechEngine(self, willSpeak: range, of: request) }
    func finish(_ request: SpeechRequest) { delegate?.speechEngine(self, didFinish: request) }

    func play(_ request: SpeechRequest) {
        start(request)
        finish(request)
    }
}

@MainActor
@Suite("Reading queue")
struct ReadingQueueTests {
    private let sentences = ["One.", "Two.", "Three.", "Four."]

    @Test func startQueuesOnlyTheLookahead() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine, lookahead: 2)
        queue.start(sentences, settings: SpeechVoiceSettings())
        #expect(queue.state == .speaking)
        #expect(engine.spoken.map(\.text) == ["One.", "Two."])
        #expect(queue.currentSentence == "One.")
    }

    @Test func finishingASentenceQueuesTheNext() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine, lookahead: 2)
        queue.start(sentences, settings: SpeechVoiceSettings())
        engine.play(engine.spoken[0])
        engine.start(engine.spoken[1])
        #expect(queue.currentIndex == 1)
        #expect(engine.spoken.map(\.text) == ["One.", "Two.", "Three."])
    }

    @Test func readsToTheEndAndFinishes() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine)
        var finished = 0
        queue.onFinish = { finished += 1 }
        queue.start(sentences, settings: SpeechVoiceSettings())
        var played = 0
        while played < engine.spoken.count {
            engine.play(engine.spoken[played])
            played += 1
        }
        #expect(engine.spoken.map(\.text) == sentences)
        #expect(queue.state == .idle)
        #expect(finished == 1)
    }

    @Test func stopSilencesTheEngineAndIgnoresLateCallbacks() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine)
        var finished = 0
        queue.onFinish = { finished += 1 }
        queue.start(sentences, settings: SpeechVoiceSettings())
        let stale = engine.spoken[0]
        let stopsBefore = engine.stopCount
        queue.stop()
        #expect(engine.stopCount == stopsBefore + 1)
        #expect(queue.state == .idle)
        #expect(finished == 1)
        engine.play(stale)
        #expect(engine.spoken.count == 2)
        #expect(finished == 1)
    }

    @Test func skipForwardRestartsFromTheNextSentence() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine)
        queue.start(sentences, settings: SpeechVoiceSettings())
        let stale = engine.spoken[1]
        queue.skip(by: 1)
        #expect(queue.currentIndex == 1)
        #expect(engine.spoken.suffix(2).map(\.text) == ["Two.", "Three."])
        engine.finish(stale)
        #expect(engine.spoken.count == 4)
    }

    @Test func skipBackStopsAtTheFirstSentence() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine)
        queue.start(sentences, settings: SpeechVoiceSettings())
        queue.skip(by: -1)
        #expect(queue.currentIndex == 0)
        #expect(engine.spoken.last?.text == "Two.")
        #expect(engine.spoken.dropLast().last?.text == "One.")
    }

    @Test func skipForwardFromTheLastSentenceStops() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine, lookahead: 1)
        queue.start(["Only."], settings: SpeechVoiceSettings())
        queue.skip(by: 1)
        #expect(queue.state == .idle)
    }

    @Test func jumpRestartsAtTheChosenSentence() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine)
        queue.start(sentences, settings: SpeechVoiceSettings())
        queue.pause()
        queue.jump(to: 2)
        #expect(queue.currentIndex == 2)
        #expect(queue.state == .speaking)
        #expect(engine.spoken.suffix(2).map(\.text) == ["Three.", "Four."])
    }

    @Test func jumpOutOfRangeOrWhileIdleDoesNothing() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine)
        queue.jump(to: 1)
        #expect(queue.state == .idle)
        queue.start(sentences, settings: SpeechVoiceSettings())
        let spoken = engine.spoken.count
        queue.jump(to: 9)
        #expect(engine.spoken.count == spoken)
    }

    @Test func pauseAndResume() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine)
        queue.start(sentences, settings: SpeechVoiceSettings())
        queue.togglePause()
        #expect(queue.state == .paused)
        #expect(engine.pauseCount == 1)
        queue.togglePause()
        #expect(queue.state == .speaking)
        #expect(engine.resumeCount == 1)
    }

    @Test func pauseIsIgnoredWhenIdle() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine)
        queue.togglePause()
        #expect(queue.state == .idle)
        #expect(engine.pauseCount == 0)
    }

    @Test func changingSpeedRestartsAtTheCurrentWordWhenTheEngineCannotChangeLive() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine)
        queue.start(["The first sentence is here.", "Then the second."], settings: SpeechVoiceSettings(rateMultiplier: 1))
        let first = engine.spoken[0]
        engine.start(first)
        engine.word(NSRange(location: 10, length: 8), in: first)
        queue.update(settings: SpeechVoiceSettings(rateMultiplier: 1.5))

        let restarted = engine.spoken.suffix(2)
        #expect(restarted.map(\.text) == ["sentence is here.", "Then the second."])
        #expect(restarted.map(\.textOffset) == [10, 0])
        #expect(restarted.allSatisfy { $0.settings.rateMultiplier == 1.5 })
        #expect(queue.currentIndex == 0)
        #expect(queue.spokenRange == NSRange(location: 10, length: 8))

        let resumed = restarted.first!
        engine.start(resumed)
        #expect(queue.spokenRange == NSRange(location: 10, length: 8))
        engine.word(NSRange(location: 9, length: 2), in: resumed)
        #expect(queue.spokenRange == NSRange(location: 19, length: 2))
    }

    @Test func changingSpeedBeforeAnyWordRestartsTheSentence() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine)
        queue.start(sentences, settings: SpeechVoiceSettings(rateMultiplier: 1))
        engine.play(engine.spoken[0])
        engine.start(engine.spoken[1])
        queue.update(settings: SpeechVoiceSettings(rateMultiplier: 1.5))
        let restarted = engine.spoken.suffix(2)
        #expect(restarted.map(\.text) == ["Two.", "Three."])
        #expect(restarted.allSatisfy { $0.textOffset == 0 && $0.settings.rateMultiplier == 1.5 })
    }

    @Test func liveSpeedChangesDoNotRestartAnything() {
        let engine = FakeEngine()
        engine.changesRateLive = true
        let queue = ReadingQueue(engine: engine)
        queue.start(sentences, settings: SpeechVoiceSettings(rateMultiplier: 1))
        engine.start(engine.spoken[0])
        engine.word(NSRange(location: 0, length: 3), in: engine.spoken[0])
        let stops = engine.stopCount
        let spoken = engine.spoken.count
        queue.update(settings: SpeechVoiceSettings(rateMultiplier: 1.75))
        #expect(engine.rateChanges == [1.75])
        #expect(engine.stopCount == stops)
        #expect(engine.spoken.count == spoken)
        #expect(queue.state == .speaking)
        #expect(queue.currentSettings.rateMultiplier == 1.75)
        engine.play(engine.spoken[0])
        #expect(engine.spoken.last?.settings.rateMultiplier == 1.75)
    }

    @Test func changingVoiceRestartsAtTheCurrentWordEvenWithLiveRate() {
        let engine = FakeEngine()
        engine.changesRateLive = true
        let queue = ReadingQueue(engine: engine)
        queue.start(["Alpha beta gamma."], settings: SpeechVoiceSettings(voiceIdentifier: "a"))
        engine.start(engine.spoken[0])
        engine.word(NSRange(location: 6, length: 4), in: engine.spoken[0])
        queue.update(settings: SpeechVoiceSettings(voiceIdentifier: "b"))
        #expect(engine.rateChanges.isEmpty)
        #expect(engine.spoken.last?.text == "beta gamma.")
        #expect(engine.spoken.last?.settings.voiceIdentifier == "b")
    }

    @Test func speedChangeWhilePausedContinuesFromTheCurrentWordOnResume() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine)
        queue.start(["One two three four."], settings: SpeechVoiceSettings())
        engine.start(engine.spoken[0])
        engine.word(NSRange(location: 8, length: 5), in: engine.spoken[0])
        queue.pause()
        let queued = engine.spoken.count
        queue.update(settings: SpeechVoiceSettings(rateMultiplier: 2))
        #expect(engine.spoken.count == queued)
        queue.resume()
        #expect(engine.resumeCount == 0)
        #expect(engine.spoken.last?.text == "three four.")
        #expect(engine.spoken.last?.settings.rateMultiplier == 2)
        #expect(queue.state == .speaking)
    }

    @Test func liveSpeedChangeWhilePausedJustResumes() {
        let engine = FakeEngine()
        engine.changesRateLive = true
        let queue = ReadingQueue(engine: engine)
        queue.start(sentences, settings: SpeechVoiceSettings())
        queue.pause()
        let spoken = engine.spoken.count
        queue.update(settings: SpeechVoiceSettings(rateMultiplier: 0.75))
        queue.resume()
        #expect(engine.resumeCount == 1)
        #expect(engine.spoken.count == spoken)
        #expect(engine.rateChanges == [0.75])
    }

    @Test func wordRangesAreTrackedForTheCurrentSentence() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine)
        queue.start(sentences, settings: SpeechVoiceSettings())
        engine.start(engine.spoken[0])
        engine.word(NSRange(location: 0, length: 3), in: engine.spoken[0])
        #expect(queue.spokenRange == NSRange(location: 0, length: 3))
        engine.word(NSRange(location: 0, length: 3), in: engine.spoken[1])
        #expect(queue.spokenRange == NSRange(location: 0, length: 3))
        engine.start(engine.spoken[1])
        #expect(queue.spokenRange == nil)
    }

    @Test func emptyInputDoesNotStart() {
        let engine = FakeEngine()
        let queue = ReadingQueue(engine: engine)
        queue.start(["  ", ""], settings: SpeechVoiceSettings())
        #expect(queue.state == .idle)
        #expect(engine.spoken.isEmpty)
    }

    @Test func rateIsClampedToTheSupportedRange() {
        #expect(SpeechVoiceSettings(rateMultiplier: 5).rateMultiplier == 2)
        #expect(SpeechVoiceSettings(rateMultiplier: 0.1).rateMultiplier == 0.5)
    }
}
