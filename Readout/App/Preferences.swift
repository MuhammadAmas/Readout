import Foundation
import ReadoutCore

enum Preferences {
    static let voiceIdentifier = "voiceIdentifier"
    static let speechRate = "speechRate"
    static let matchTextLanguage = "matchTextLanguage"
    static let cleanupEnabled = "cleanupEnabled"
    static let skipCodeBlocks = "skipCodeBlocks"
    static let codeBlockMode = "codeBlockMode"
    static let technicalSpeech = "technicalSpeech"
    static let pronunciations = "pronunciations"
    static let showMiniPlayer = "showMiniPlayer"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let automaticUpdates = "automaticUpdates"

    enum Defaults {
        static let voiceIdentifier = ""
        static let speechRate = 1.0
        static let matchTextLanguage = true
        static let cleanupEnabled = true
        static let codeBlockMode = CodeBlockMode.skip.rawValue
        static let technicalSpeech = true
        static let showMiniPlayer = true
        static let automaticUpdates = true
    }

    static let rateSteps: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    static func register() {
        let legacySkip = UserDefaults.standard.object(forKey: skipCodeBlocks) as? Bool
        let codeBlocks = legacySkip == false ? CodeBlockMode.read.rawValue : Defaults.codeBlockMode
        UserDefaults.standard.register(defaults: [
            voiceIdentifier: Defaults.voiceIdentifier,
            speechRate: Defaults.speechRate,
            matchTextLanguage: Defaults.matchTextLanguage,
            cleanupEnabled: Defaults.cleanupEnabled,
            codeBlockMode: codeBlocks,
            technicalSpeech: Defaults.technicalSpeech,
            showMiniPlayer: Defaults.showMiniPlayer,
            automaticUpdates: Defaults.automaticUpdates,
            hasCompletedOnboarding: false,
        ])
    }

    static var cleanupOptions: CleanupOptions {
        let defaults = UserDefaults.standard
        return CleanupOptions(
            isEnabled: defaults.bool(forKey: cleanupEnabled),
            codeBlocks: defaults.string(forKey: codeBlockMode).flatMap(CodeBlockMode.init(rawValue:)) ?? .skip,
            speaksTechnicalTerms: defaults.bool(forKey: technicalSpeech),
            pronunciations: savedPronunciations
        )
    }

    static var savedPronunciations: [Pronunciation] {
        guard let data = UserDefaults.standard.data(forKey: pronunciations) else { return [] }
        return (try? JSONDecoder().decode([Pronunciation].self, from: data)) ?? []
    }

    static func save(pronunciations entries: [Pronunciation]) {
        let data = try? JSONEncoder().encode(entries)
        UserDefaults.standard.set(data, forKey: pronunciations)
    }

    static var rate: Double {
        let value = UserDefaults.standard.double(forKey: speechRate)
        return value == 0 ? Defaults.speechRate : value
    }

    static func formatted(rate: Double) -> String {
        let text = rate.formatted(.number.precision(.fractionLength(0...2)))
        return "\(text)×"
    }
}
