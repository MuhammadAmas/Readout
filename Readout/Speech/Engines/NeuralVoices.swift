import Foundation

enum NeuralVoiceInstallation {
    static let modelName = "kokoro-multi-lang-v1_0"
    static let fetchScript = "scripts/fetch-neural-voice.sh"

    static var directory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Readout/Neural", isDirectory: true)
    }

    static var runtimeLibrary: URL {
        directory.appendingPathComponent("runtime/lib/libsherpa-onnx-c-api.dylib")
    }

    static var modelDirectory: URL {
        directory.appendingPathComponent(modelName, isDirectory: true)
    }

    static var isInstalled: Bool {
        let required = [
            runtimeLibrary,
            modelDirectory.appendingPathComponent("model.onnx"),
            modelDirectory.appendingPathComponent("voices.bin"),
            modelDirectory.appendingPathComponent("tokens.txt"),
            modelDirectory.appendingPathComponent("espeak-ng-data"),
            modelDirectory.appendingPathComponent(KokoroVoice.Accent.american.lexicon),
            modelDirectory.appendingPathComponent(KokoroVoice.Accent.british.lexicon),
        ]
        return required.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }
}

struct KokoroVoice: Hashable, Sendable {
    enum Accent: Hashable, Sendable {
        case american
        case british

        var language: String {
            switch self {
            case .american: "en-US"
            case .british: "en-GB"
            }
        }

        var lexicon: String {
            switch self {
            case .american: "lexicon-us-en.txt"
            case .british: "lexicon-gb-en.txt"
            }
        }

        var espeakLanguage: String {
            switch self {
            case .american: "en-us"
            case .british: "en-gb"
            }
        }
    }

    static let identifierPrefix = "kokoro:"

    let code: String
    let speakerID: Int32

    var identifier: String { Self.identifierPrefix + code }
    var accent: Accent { code.hasPrefix("b") ? .british : .american }
    var isFemale: Bool { code.dropFirst().first == "f" }

    var name: String {
        let base = code.split(separator: "_").last.map(String.init) ?? code
        return base.prefix(1).uppercased() + base.dropFirst()
    }

    var label: String {
        "\(name) (Neural, \(isFemale ? "female" : "male"))"
    }

    static let all: [KokoroVoice] = [
        KokoroVoice(code: "af_heart", speakerID: 3),
        KokoroVoice(code: "af_bella", speakerID: 2),
        KokoroVoice(code: "bf_emma", speakerID: 21),
        KokoroVoice(code: "af_nicole", speakerID: 6),
        KokoroVoice(code: "am_michael", speakerID: 16),
        KokoroVoice(code: "am_fenrir", speakerID: 14),
        KokoroVoice(code: "am_puck", speakerID: 18),
        KokoroVoice(code: "bm_george", speakerID: 26),
        KokoroVoice(code: "bm_fable", speakerID: 25),
        KokoroVoice(code: "bf_isabella", speakerID: 22),
        KokoroVoice(code: "af_aoede", speakerID: 1),
        KokoroVoice(code: "af_kore", speakerID: 5),
        KokoroVoice(code: "af_sarah", speakerID: 9),
        KokoroVoice(code: "af_nova", speakerID: 7),
        KokoroVoice(code: "af_alloy", speakerID: 0),
        KokoroVoice(code: "af_sky", speakerID: 10),
        KokoroVoice(code: "bm_lewis", speakerID: 27),
        KokoroVoice(code: "af_jessica", speakerID: 4),
        KokoroVoice(code: "af_river", speakerID: 8),
        KokoroVoice(code: "am_echo", speakerID: 12),
        KokoroVoice(code: "am_eric", speakerID: 13),
        KokoroVoice(code: "am_liam", speakerID: 15),
        KokoroVoice(code: "am_onyx", speakerID: 17),
        KokoroVoice(code: "bf_alice", speakerID: 20),
        KokoroVoice(code: "bf_lily", speakerID: 23),
        KokoroVoice(code: "bm_daniel", speakerID: 24),
        KokoroVoice(code: "am_adam", speakerID: 11),
    ]

    static func voice(identifier: String) -> KokoroVoice? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let code = identifier.dropFirst(identifierPrefix.count)
        return all.first { $0.code == code }
    }
}
