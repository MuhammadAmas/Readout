import Foundation
import NaturalLanguage

public enum LanguageDetector {
    public static func dominantLanguage(of text: String, minimumConfidence: Double = 0.75) -> String? {
        let sample = String(text.prefix(2000))
        guard sample.filter(\.isLetter).count >= 12 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence >= minimumConfidence
        else { return nil }
        return language.rawValue
    }

    public static func baseLanguage(_ code: String) -> String {
        String(code.lowercased().prefix(while: { $0 != "-" && $0 != "_" }))
    }

    public static func isSameLanguage(_ first: String, _ second: String) -> Bool {
        baseLanguage(first) == baseLanguage(second)
    }
}
