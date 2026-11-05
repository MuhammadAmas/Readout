import AVFoundation
import ReadoutCore

@MainActor
final class NeuralSpeechEngine: SpeechEngine {
    weak var delegate: (any SpeechEngineDelegate)?

    private final class Item {
        let request: SpeechRequest
        let pieces: [NSRange]
        var durations: [Int: TimeInterval] = [:]
        var scheduled = 0
        var played = 0
        var started = false

        init(request: SpeechRequest, pieces: [NSRange]) {
            self.request = request
            self.pieces = pieces
        }

        var isComplete: Bool { played == pieces.count }
    }

    private struct Playhead {
        let item: Item
        let piece: Int
        var startedAt: Date
        var wordIndex = -1
    }

    private let worker = KokoroWorker.shared
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var items: [Item] = []
    private var playhead: Playhead?
    private var token = CancelToken()
    private var generation = 0
    private var isPaused = false
    private var pausedAt: Date?
    private var highlightTimer: Timer?
    private var idleWork: DispatchWorkItem?
    private let audioQueue = DispatchQueue(label: "dev.readout.audio", qos: .userInitiated)
    private let audioTimeout: TimeInterval = 4
    private var isAudioReady = false
    private var isStartingAudio = false
    private var audioSetup = 0
    private var waitingForAudio: [(Bool) -> Void] = []

    init() {
        engine.attach(player)
    }

    var isPlaying: Bool { player.isPlaying }

    func prepare(_ voice: KokoroVoice) {
        worker.preload(voice.accent)
        withAudio(sampleRate: Self.kokoroSampleRate) { [weak self] _ in
            guard let self, self.items.isEmpty else { return }
            self.scheduleIdle()
        }
    }

    private static let kokoroSampleRate: Double = 24_000

    func speak(_ request: SpeechRequest) {
        guard let voice = request.settings.voiceIdentifier.flatMap(KokoroVoice.voice(identifier:)) else { return }
        let quickStart = items.isEmpty && playhead == nil
        let pieces = Self.pieces(of: request.text, quickStart: quickStart)
        let item = Item(request: request, pieces: pieces)
        items.append(item)

        let text = request.text as NSString
        let generation = generation
        worker.render(
            pieces.map { text.substring(with: $0) },
            voice: voice,
            speed: Float(request.settings.rateMultiplier),
            token: token
        ) { [weak self] index, samples, sampleRate in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.deliver(samples, sampleRate: sampleRate, piece: index, of: item, generation: generation)
                }
            }
        }
    }

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        pausedAt = Date()
        player.pause()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        if let pausedAt, var playhead {
            playhead.startedAt += Date().timeIntervalSince(pausedAt)
            self.playhead = playhead
        }
        pausedAt = nil
        if engine.isRunning {
            player.play()
        }
    }

    func stop() {
        generation += 1
        token.cancel()
        token = CancelToken()
        items.removeAll()
        playhead = nil
        isPaused = false
        pausedAt = nil
        player.stop()
        stopHighlighting()
        scheduleIdle()
    }

    private func deliver(_ samples: [Float]?, sampleRate: Double, piece: Int, of item: Item, generation: Int) {
        guard generation == self.generation, items.contains(where: { $0 === item }) else { return }
        guard let samples, !samples.isEmpty, let buffer = makeBuffer(samples, sampleRate: sampleRate) else {
            Log.speech.error("Kokoro produced no audio for a sentence; skipping it")
            skip(piece: piece, of: item)
            return
        }
        withAudio(sampleRate: sampleRate) { [weak self] ready in
            guard let self, generation == self.generation, self.items.contains(where: { $0 === item }) else { return }
            guard ready else {
                self.skip(piece: piece, of: item)
                return
            }
            self.schedule(buffer, duration: Double(samples.count) / sampleRate, piece: piece, of: item, generation: generation)
        }
    }

    private func skip(piece: Int, of item: Item) {
        item.scheduled += 1
        item.played += 1
        if item.isComplete { finish(item) }
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, duration: TimeInterval, piece: Int, of item: Item, generation: Int) {
        item.durations[piece] = duration
        item.scheduled += 1
        player.volume = item.request.settings.volume
        let wasIdle = playhead == nil
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.played(piece: piece, of: item, generation: generation)
                }
            }
        }
        if !isPaused, !player.isPlaying {
            player.play()
        }
        if wasIdle, items.first === item, item.played == piece {
            begin(piece: piece, of: item)
        }
    }

    private func played(piece: Int, of item: Item, generation: Int) {
        guard generation == self.generation, items.contains(where: { $0 === item }) else { return }
        item.played += 1
        playhead = nil
        if item.isComplete {
            finish(item)
        } else if item.scheduled > item.played {
            begin(piece: item.played, of: item)
        }
    }

    private func finish(_ item: Item) {
        items.removeAll { $0 === item }
        delegate?.speechEngine(self, didFinish: item.request)
        if let next = items.first, next.scheduled > next.played {
            begin(piece: next.played, of: next)
        }
        if items.isEmpty {
            stopHighlighting()
            scheduleIdle()
        }
    }

    private func begin(piece: Int, of item: Item) {
        playhead = Playhead(item: item, piece: piece, startedAt: Date())
        if !item.started {
            item.started = true
            delegate?.speechEngine(self, didStart: item.request)
        }
        startHighlighting()
    }

    private func startHighlighting() {
        idleWork?.cancel()
        guard highlightTimer == nil else { return }
        highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHighlight() }
        }
    }

    private func stopHighlighting() {
        highlightTimer?.invalidate()
        highlightTimer = nil
    }

    private func updateHighlight() {
        guard !isPaused, var playhead, let duration = playhead.item.durations[playhead.piece], duration > 0 else { return }
        let request = playhead.item.request
        let words = Self.words(in: request.text, range: playhead.item.pieces[playhead.piece])
        guard !words.isEmpty else { return }
        let progress = min(max(Date().timeIntervalSince(playhead.startedAt) / duration, 0), 0.999)
        let index = Int(progress * Double(words.count))
        guard index != playhead.wordIndex else { return }
        playhead.wordIndex = index
        self.playhead = playhead
        delegate?.speechEngine(self, willSpeak: words[index], of: request)
    }

    private func makeBuffer(_ samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    private func withAudio(sampleRate: Double, _ work: @escaping (Bool) -> Void) {
        idleWork?.cancel()
        if isAudioReady, format?.sampleRate == sampleRate, engine.isRunning {
            work(true)
            return
        }
        waitingForAudio.append(work)
        guard !isStartingAudio else { return }
        isStartingAudio = true
        audioSetup += 1
        let setup = audioSetup
        let engine = engine
        let player = player
        audioQueue.async { [weak self] in
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            var started = engine.isRunning
            if !started {
                engine.prepare()
                do {
                    try engine.start()
                    started = true
                } catch {
                    Log.speech.error("Audio engine failed to start: \(error.localizedDescription, privacy: .public)")
                }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, setup == self.audioSetup else { return }
                    self.format = format
                    self.finishAudioSetup(ready: started)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + audioTimeout) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, setup == self.audioSetup, self.isStartingAudio else { return }
                Log.speech.error("macOS audio didn't respond within \(Int(self.audioTimeout), privacy: .public) s; skipping neural audio")
                self.audioSetup += 1
                self.finishAudioSetup(ready: false)
            }
        }
    }

    private func finishAudioSetup(ready: Bool) {
        isStartingAudio = false
        isAudioReady = ready
        let waiting = waitingForAudio
        waitingForAudio.removeAll()
        waiting.forEach { $0(ready) }
    }

    private func scheduleIdle() {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.items.isEmpty, !self.isStartingAudio else { return }
                self.isAudioReady = false
                let engine = self.engine
                self.audioQueue.async { engine.pause() }
            }
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    static func pieces(of text: String, quickStart: Bool) -> [NSRange] {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        guard quickStart, text.count > 70 else { return [whole] }
        let characters = Array(text)
        let clauseBreaks: Set<Character> = [",", ";", ":", "—", "–"]
        var split: Int?
        for index in 20..<min(characters.count - 20, 90) where clauseBreaks.contains(characters[index]) {
            split = index + 1
            break
        }
        if split == nil {
            split = (25..<min(characters.count - 20, 55)).reversed().first { characters[$0] == " " }
        }
        guard let split else { return [whole] }
        let head = String(characters[..<split])
        let headLength = (head as NSString).length
        return [
            NSRange(location: 0, length: headLength),
            NSRange(location: headLength, length: whole.length - headLength),
        ]
    }

    static func words(in text: String, range: NSRange) -> [NSRange] {
        var words: [NSRange] = []
        (text as NSString).enumerateSubstrings(in: range, options: [.byWords, .substringNotRequired]) { _, wordRange, _, _ in
            words.append(wordRange)
        }
        return words
    }
}
