import AppKit
import AVFoundation
import ReadoutCore

@MainActor
enum SelfTest {
    private final class Probe: SpeechEngineDelegate {
        var started: Date?
        var finished: Date?

        func speechEngine(_ engine: any SpeechEngine, didStart request: SpeechRequest) {
            started = started ?? Date()
        }

        func speechEngine(_ engine: any SpeechEngine, willSpeak range: NSRange, of request: SpeechRequest) {}

        func speechEngine(_ engine: any SpeechEngine, didFinish request: SpeechRequest) {
            finished = Date()
        }
    }

    private struct Check {
        let name: String
        let passed: Bool
        let detail: String
    }

    static func run() {
        Task { @MainActor in
            var checks: [Check] = []
            let document = sampleDocument(words: 5_000)

            let preparationStart = Date()
            let sentences = SentenceSplitter.split(TextCleaner.clean(document))
            let preparation = Date().timeIntervalSince(preparationStart)
            checks.append(Check(
                name: "Clean and split 5,000 words",
                passed: preparation < 0.25 && sentences.count > 100,
                detail: "\(sentences.count) sentences in \(milliseconds(preparation))"
            ))

            let voice = SpeechVoiceSettings(voiceIdentifier: AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())?.identifier)
            for attempt in ["cold", "warm"] {
                let latency = await firstAudio(for: sentences[0], voice: voice)
                let total = preparation + (latency ?? 10)
                checks.append(Check(
                    name: "Selection to first audio (\(attempt) engine)",
                    passed: latency != nil && total < 1.0,
                    detail: latency == nil ? "speech never started" : "\(milliseconds(total)) including clean-up"
                ))
            }

            let stopLatency = await stopLatency(voice: voice)
            checks.append(Check(
                name: "Stop while speaking",
                passed: stopLatency.map { $0 < 0.5 } ?? false,
                detail: stopLatency.map { "silent after \(milliseconds($0))" } ?? "synthesizer kept speaking"
            ))

            checks.append(pasteboardRoundTrip())
            checks.append(contentsOf: await neuralChecks())

            let voices = VoiceCatalog.options()
            let neural = voices.filter(\.isNeural).count
            let better = voices.filter { $0.isHighQuality && !$0.isNeural }.count
            let automatic = VoiceCatalog.bestVoice(forLanguage: AVSpeechSynthesisVoice.currentLanguageCode())
            checks.append(Check(
                name: "Installed voices",
                passed: !voices.isEmpty,
                detail: "\(voices.count) voices (\(neural) neural, \(better) Premium or Enhanced); Automatic uses \(automatic?.label ?? "the system default")"
            ))

            checks.append(Check(
                name: "Accessibility access",
                passed: true,
                detail: AccessibilityPermission.isTrusted ? "granted" : "not granted yet (needed for real selections, not for this test)"
            ))

            var lines = checks.map { "\($0.passed ? "PASS" : "FAIL")  \($0.name): \($0.detail)" }
            let failed = checks.filter { !$0.passed }.count
            lines.append(failed == 0 ? "All self-tests passed." : "\(failed) self-test(s) failed.")
            let report = lines.joined(separator: "\n")
            print(report)
            let arguments = CommandLine.arguments
            if let index = arguments.firstIndex(of: "--report"), arguments.indices.contains(index + 1) {
                try? (report + "\n").write(toFile: arguments[index + 1], atomically: true, encoding: .utf8)
            }
            KokoroWorker.shared.shutDown(timeout: 3)
            exit(failed == 0 ? 0 : 1)
        }
    }

    private static func neuralChecks() async -> [Check] {
        guard NeuralVoiceInstallation.isInstalled, let heart = KokoroVoice.voice(identifier: "kokoro:af_heart") else {
            return [Check(name: "Neural voice", passed: true, detail: "not installed, skipped")]
        }
        var checks: [Check] = []

        let loadStart = Date()
        let loaded = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let synthesizer = try? KokoroSynthesizer(accent: .american, threads: 6)
                let samples = synthesizer?.synthesize("Readout checks that this voice makes sound.", speakerID: heart.speakerID, speed: 1, cancel: CancelToken())
                continuation.resume(returning: (synthesizer != nil, samples ?? [], synthesizer?.sampleRate ?? 1))
            }
        }
        let loadTime = Date().timeIntervalSince(loadStart)
        let rms = loaded.1.isEmpty ? 0 : (loaded.1.reduce(0) { $0 + $1 * $1 } / Float(loaded.1.count)).squareRoot()
        let seconds = Double(loaded.1.count) / loaded.2
        checks.append(Check(
            name: "Neural model loads and makes sound",
            passed: loaded.0 && rms > 0.01 && seconds > 1,
            detail: loaded.0 ? "loaded and spoke \(String(format: "%.1f", seconds)) s of audio (RMS \(String(format: "%.3f", rms))) in \(milliseconds(loadTime))" : "failed to load"
        ))

        let settings = SpeechVoiceSettings(voiceIdentifier: heart.identifier, volume: 0)
        let long = "Readout splits a long opening sentence like this one, which keeps going with clause after clause, so that the first few words can start playing almost immediately while the neural model quietly renders the rest of the sentence in the background without any gap."
        for (name, text) in [("typical", "Readout speaks the selected text sentence by sentence, so the first words play while the rest waits."), ("long", long)] {
            let engine = NeuralSpeechEngine()
            engine.prepare(heart)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let probe = Probe()
            engine.delegate = probe
            let start = Date()
            engine.speak(SpeechRequest(id: 0, sentenceIndex: 0, text: text, settings: settings))
            let deadline = start.addingTimeInterval(5)
            while probe.started == nil, Date() < deadline {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            let latency = probe.started.map { $0.timeIntervalSince(start) }
            checks.append(Check(
                name: "Neural first audio (\(name) sentence, \(text.count) chars)",
                passed: latency.map { $0 < 1.0 } ?? false,
                detail: latency.map { "started after \(milliseconds($0))" } ?? "never started"
            ))
            if name == "long" {
                try? await Task.sleep(nanoseconds: 400_000_000)
                let stopStart = Date()
                engine.stop()
                let stopTime = Date().timeIntervalSince(stopStart)
                checks.append(Check(
                    name: "Neural stop while speaking",
                    passed: !engine.isPlaying && stopTime < 0.5,
                    detail: "silent after \(milliseconds(stopTime))"
                ))
            } else {
                engine.stop()
            }
        }
        return checks
    }

    private static func firstAudio(for sentence: String, voice: SpeechVoiceSettings) async -> TimeInterval? {
        let engine = SystemSpeechEngine()
        let probe = Probe()
        engine.delegate = probe
        let start = Date()
        engine.speak(request(sentence, voice))
        let deadline = start.addingTimeInterval(3)
        while probe.started == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        engine.stop()
        return probe.started.map { $0.timeIntervalSince(start) }
    }

    private static func stopLatency(voice: SpeechVoiceSettings) async -> TimeInterval? {
        let synthesizer = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: String(repeating: "This sentence keeps the synthesizer busy for a while. ", count: 20))
        utterance.volume = 0
        utterance.voice = voice.voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
        synthesizer.speak(utterance)
        let warmup = Date().addingTimeInterval(3)
        while !synthesizer.isSpeaking, Date() < warmup {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard synthesizer.isSpeaking else { return nil }
        let start = Date()
        synthesizer.stopSpeaking(at: .immediate)
        let deadline = start.addingTimeInterval(2)
        while synthesizer.isSpeaking, Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return synthesizer.isSpeaking ? nil : Date().timeIntervalSince(start)
    }

    private static func pasteboardRoundTrip() -> Check {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("dev.readout.selftest.\(ProcessInfo.processInfo.processIdentifier)"))
        defer { pasteboard.releaseGlobally() }

        let first = NSPasteboardItem()
        first.setString("Original clipboard text", forType: .string)
        first.setString("<b>Original</b>", forType: .html)
        first.setData(Data([0, 1, 2, 3, 255]), forType: NSPasteboard.PasteboardType("org.chromium.web-custom-data"))
        let second = NSPasteboardItem()
        second.setData(Data(repeating: 7, count: 2048), forType: .png)
        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])

        let before = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("Text copied from the selection", forType: .string)
        before.restore(to: pasteboard)
        let after = PasteboardSnapshot(pasteboard)

        let types = before.items.map(\.count).reduce(0, +)
        return Check(
            name: "Clipboard restored exactly",
            passed: before == after && types == 4,
            detail: "\(before.items.count) items, \(types) types compared byte for byte"
        )
    }

    private static func request(_ text: String, _ voice: SpeechVoiceSettings) -> SpeechRequest {
        SpeechRequest(
            id: 0,
            sentenceIndex: 0,
            text: text,
            settings: SpeechVoiceSettings(voiceIdentifier: voice.voiceIdentifier, rateMultiplier: voice.rateMultiplier, volume: 0)
        )
    }

    private static func sampleDocument(words target: Int) -> String {
        let paragraph = """
        ## Section
        Readout speaks the **selected** text sentence by sentence, so the first words play while the rest waits. \
        It sends nothing over the network & cleans Markdown first, e.g. tables -> sentences. See https://example.com/docs.

        | Column | Value |
        |---|---|
        | Speed | Fast |
        """
        var document = ""
        while document.split(whereSeparator: \.isWhitespace).count < target {
            document += paragraph + "\n\n"
        }
        return document
    }

    private static func milliseconds(_ interval: TimeInterval) -> String {
        "\(Int((interval * 1000).rounded())) ms"
    }
}
