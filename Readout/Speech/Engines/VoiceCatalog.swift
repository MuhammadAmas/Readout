import AVFoundation
import ReadoutCore

struct VoiceOption: Identifiable, Hashable {
    enum Tier: Hashable {
        case neural(order: Int)
        case premium
        case enhanced
        case standard
        case eloquence
        case novelty
    }

    let id: String
    let name: String
    let language: String
    let tier: Tier
    let detail: String?

    var isNeural: Bool {
        if case .neural = tier { return true }
        return false
    }

    var isHighQuality: Bool {
        switch tier {
        case .neural, .premium, .enhanced: true
        default: false
        }
    }

    var label: String {
        switch tier {
        case .neural: detail ?? "\(name) (Neural)"
        case .premium: "\(name) (Premium)"
        case .enhanced: "\(name) (Enhanced)"
        default: name
        }
    }

    var rank: Int {
        switch tier {
        case .neural(let order): 1_000 - order
        case .premium: 4
        case .enhanced: 3
        case .standard: 2
        case .eloquence: 1
        case .novelty: 0
        }
    }
}

struct LanguageGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let voices: [VoiceOption]

    var hasHighQualityVoice: Bool { voices.contains(where: \.isHighQuality) }
}

enum VoiceCatalog {
    static func options() -> [VoiceOption] {
        neuralOptions() + systemOptions()
    }

    static func neuralOptions() -> [VoiceOption] {
        guard NeuralVoiceInstallation.isInstalled else { return [] }
        return KokoroVoice.all.enumerated().map { order, voice in
            VoiceOption(
                id: voice.identifier,
                name: voice.name,
                language: voice.accent.language,
                tier: .neural(order: order),
                detail: voice.label
            )
        }
    }

    static func systemOptions() -> [VoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { !$0.voiceTraits.contains(.isPersonalVoice) }
            .map(option(for:))
    }

    static func option(identifier: String) -> VoiceOption? {
        if KokoroVoice.voice(identifier: identifier) != nil {
            return neuralOptions().first { $0.id == identifier }
        }
        return AVSpeechSynthesisVoice(identifier: identifier).map(option(for:))
    }

    static func groups() -> [LanguageGroup] {
        let preferred = Locale.preferredLanguages
        let grouped = Dictionary(grouping: options(), by: \.language)
        return grouped
            .map { language, voices in
                LanguageGroup(
                    id: language,
                    title: Locale.current.localizedString(forIdentifier: language) ?? language,
                    voices: voices.sorted(by: voiceOrder)
                )
            }
            .sorted { first, second in
                let firstPriority = priority(of: first.id, preferred: preferred)
                let secondPriority = priority(of: second.id, preferred: preferred)
                if firstPriority != secondPriority { return firstPriority < secondPriority }
                return first.title.localizedStandardCompare(second.title) == .orderedAscending
            }
    }

    static func bestVoice(forLanguage language: String) -> VoiceOption? {
        let candidates = options().filter { LanguageDetector.isSameLanguage($0.language, language) && $0.tier != .novelty }
        let regional = Locale.current.region.map { "\(LanguageDetector.baseLanguage(language))-\($0.identifier)".lowercased() }
        let systemDefault = AVSpeechSynthesisVoice(language: language)?.identifier
        return candidates.max { first, second in
            let firstExact = matches(first.language, language, regional)
            let secondExact = matches(second.language, language, regional)
            if first.isNeural, second.isNeural, firstExact != secondExact { return !firstExact }
            if first.rank != second.rank { return first.rank < second.rank }
            if (first.id == systemDefault) != (second.id == systemDefault) { return second.id == systemDefault }
            if firstExact != secondExact { return !firstExact }
            return first.name > second.name
        }
    }

    private static func option(for voice: AVSpeechSynthesisVoice) -> VoiceOption {
        VoiceOption(id: voice.identifier, name: voice.name, language: voice.language, tier: tier(of: voice), detail: nil)
    }

    private static func tier(of voice: AVSpeechSynthesisVoice) -> VoiceOption.Tier {
        if voice.voiceTraits.contains(.isNoveltyVoice) { return .novelty }
        switch voice.quality {
        case .premium: return .premium
        case .enhanced: return .enhanced
        default: return voice.identifier.contains(".eloquence.") ? .eloquence : .standard
        }
    }

    private static func matches(_ voiceLanguage: String, _ language: String, _ regional: String?) -> Bool {
        let normalized = voiceLanguage.lowercased().replacingOccurrences(of: "_", with: "-")
        return normalized == language.lowercased() || normalized == regional
    }

    private static func voiceOrder(_ first: VoiceOption, _ second: VoiceOption) -> Bool {
        if first.rank != second.rank { return first.rank > second.rank }
        return first.name.localizedStandardCompare(second.name) == .orderedAscending
    }

    private static func priority(of language: String, preferred: [String]) -> Int {
        if let index = preferred.firstIndex(where: { $0.caseInsensitiveCompare(language) == .orderedSame }) {
            return index
        }
        if let index = preferred.firstIndex(where: { LanguageDetector.isSameLanguage($0, language) }) {
            return preferred.count + index
        }
        return preferred.count * 2
    }
}
