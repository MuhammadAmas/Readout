import Foundation
import NaturalLanguage

public enum SentenceSplitter {
    public static let defaultMaximumLength = 280

    private static let listMarker = Pattern(#"^(?:\d{1,3}|[A-Za-z]|[ivxlcdmIVXLCDM]+)[.)]$"#)

    public static func split(_ text: String, maximumLength: Int = defaultMaximumLength) -> [String] {
        let limit = max(maximumLength, 40)
        let tokenizer = NLTokenizer(unit: .sentence)
        var sentences: [String] = []

        for paragraph in paragraphs(in: text) {
            tokenizer.string = paragraph
            var carried = ""
            tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
                let piece = paragraph[range].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !piece.isEmpty else { return true }
                if listMarker.matches(piece) || !piece.containsSpeakableCharacters {
                    carried += piece + " "
                    return true
                }
                sentences.append(contentsOf: chunk(carried + piece, limit: limit))
                carried = ""
                return true
            }
            let leftover = carried.trimmingCharacters(in: .whitespaces)
            if leftover.containsSpeakableCharacters {
                sentences.append(leftover)
            }
        }
        return sentences
    }

    static func paragraphs(in text: String) -> [String] {
        var paragraphs: [String] = []
        var current: [Substring] = []

        func flush() {
            let joined = current
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            if !joined.isEmpty {
                paragraphs.append(joined)
            }
            current.removeAll()
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.allSatisfy(\.isWhitespace) {
                flush()
            } else {
                current.append(line)
            }
        }
        flush()
        return paragraphs
    }

    static func chunk(_ sentence: String, limit: Int) -> [String] {
        var remaining = Substring(sentence)
        var parts: [String] = []
        let breakers: [Set<Character>] = [[",", ";", ":", "—", "–"], [" "]]

        while remaining.count > limit {
            let window = remaining.prefix(limit)
            let earliest = window.index(window.startIndex, offsetBy: limit / 3)
            var cut = window.endIndex
            for set in breakers {
                if let position = window[earliest...].lastIndex(where: { set.contains($0) }) {
                    cut = window.index(after: position)
                    break
                }
            }
            let part = remaining[..<cut].trimmingCharacters(in: .whitespaces)
            if !part.isEmpty {
                parts.append(part)
            }
            remaining = remaining[cut...].drop(while: { $0 == " " })
        }
        let tail = remaining.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty {
            parts.append(tail)
        }
        return parts
    }
}
