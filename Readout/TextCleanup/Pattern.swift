import Foundation

struct Pattern {
    struct Match {
        fileprivate let result: NSTextCheckingResult
        fileprivate let source: NSString

        subscript(group: Int) -> String? {
            guard group < result.numberOfRanges else { return nil }
            let range = result.range(at: group)
            guard range.location != NSNotFound else { return nil }
            return source.substring(with: range)
        }

        var endsSentence: Bool {
            let end = result.range.location + result.range.length
            let rest = source.substring(from: end)
            let afterSpaces = rest.drop(while: { $0 == " " || $0 == "\t" })
            guard let next = afterSpaces.first else { return true }
            return afterSpaces.startIndex != rest.startIndex && next.isUppercase
        }
    }

    private let regex: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        do {
            regex = try NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        } catch {
            preconditionFailure("Invalid pattern \(pattern): \(error)")
        }
    }

    func matches(_ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    func groups(in text: String) -> [String?]? {
        let source = text as NSString
        guard let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: source.length)) else {
            return nil
        }
        let match = Match(result: result, source: source)
        return (1..<max(result.numberOfRanges, 1)).map { match[$0] }
    }

    func replace(in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: template
        )
    }

    func replace(in text: String, using transform: (Match) -> String) -> String {
        let source = text as NSString
        let results = regex.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !results.isEmpty else { return text }
        let output = NSMutableString(string: text)
        for result in results.reversed() {
            output.replaceCharacters(in: result.range, with: transform(Match(result: result, source: source)))
        }
        return output as String
    }
}
