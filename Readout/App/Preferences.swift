import Foundation
import ReadoutCore

enum Preferences {
    static let voiceIdentifier = "voiceIdentifier"
    static let speechRate = "speechRate"
    static let matchTextLanguage = "matchTextLanguage"
    static let cleanupEnabled = "cleanupEnabled"
    static let skipCodeBlocks = "skipCodeBlocks"
    static let showMiniPlayer = "showMiniPlayer"
    static let hasCompletedOnboarding = "hasCompletedOnboarding"

    enum Defaults {
        static let voiceIdentifier = ""
        static let speechRate = 1.0
        static let matchTextLanguage = true
        static let cleanupEnabled = true
        static let skipCodeBlocks = true
        static let showMiniPlayer = true
    }

    static let rateSteps: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    static func register() {
        UserDefaults.standard.register(defaults: [
            voiceIdentifier: Defaults.voiceIdentifier,
            speechRate: Defaults.speechRate,
            matchTextLanguage: Defaults.matchTextLanguage,
            cleanupEnabled: Defaults.cleanupEnabled,
            skipCodeBlocks: Defaults.skipCodeBlocks,
            showMiniPlayer: Defaults.showMiniPlayer,
            hasCompletedOnboarding: false,
        ])
    }

    static var cleanupOptions: CleanupOptions {
        let defaults = UserDefaults.standard
        return CleanupOptions(
            isEnabled: defaults.bool(forKey: cleanupEnabled),
            skipsCodeBlocks: defaults.bool(forKey: skipCodeBlocks)
        )
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
