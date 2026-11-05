import Foundation

public struct CleanupOptions: Equatable, Sendable {
    public var isEnabled: Bool
    public var skipsCodeBlocks: Bool

    public init(isEnabled: Bool = true, skipsCodeBlocks: Bool = true) {
        self.isEnabled = isEnabled
        self.skipsCodeBlocks = skipsCodeBlocks
    }
}

public enum TextCleaner {
    public static let codeBlockNotice = "Code block skipped."

    public static func clean(_ text: String, options: CleanupOptions = CleanupOptions()) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard options.isEnabled else { return normalized }

        let lines = normalized.components(separatedBy: "\n")
        var paragraphs: [String] = []
        var prose: [String] = []
        var index = 0

        func flushProse() {
            paragraphs.append(contentsOf: ProseCleaner.paragraphs(from: prose))
            prose.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            if let fence = CodeFence(openingLine: line) {
                flushProse()
                var body: [String] = []
                index += 1
                while index < lines.count, !fence.isClosed(by: lines[index]) {
                    body.append(lines[index])
                    index += 1
                }
                index += 1
                if options.skipsCodeBlocks {
                    paragraphs.append(codeBlockNotice)
                } else {
                    paragraphs.append(contentsOf: body
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty })
                }
                continue
            }
            if let table = MarkdownTable.parse(lines, at: index) {
                flushProse()
                paragraphs.append(contentsOf: table.sentences)
                index = table.endIndex
                continue
            }
            prose.append(line)
            index += 1
        }
        flushProse()
        return paragraphs.joined(separator: "\n\n")
    }
}

struct CodeFence {
    let marker: Character
    let length: Int

    init?(openingLine line: String) {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let run = trimmed.prefix(while: { $0 == first }).count
        guard run >= 3 else { return nil }
        if first == "`", trimmed.dropFirst(run).contains("`") { return nil }
        marker = first
        length = run
    }

    func isClosed(by line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.first == marker else { return false }
        let run = trimmed.prefix(while: { $0 == marker }).count
        return run >= length && run == trimmed.count
    }
}

struct MarkdownTable {
    let sentences: [String]
    let endIndex: Int

    private static let delimiterRow = Pattern(#"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$"#)

    static func parse(_ lines: [String], at index: Int) -> MarkdownTable? {
        guard index + 1 < lines.count,
              lines[index].contains("|"),
              lines[index + 1].contains("|"),
              delimiterRow.matches(lines[index + 1])
        else { return nil }

        let headers = cells(in: lines[index]).map(header)
        var sentences: [String] = []
        var cursor = index + 2
        while cursor < lines.count {
            let line = lines[cursor]
            guard line.contains("|"), !line.trimmingCharacters(in: .whitespaces).isEmpty else { break }
            if let sentence = sentence(headers: headers, values: cells(in: line).map(InlineCleaner.clean)) {
                sentences.append(sentence)
            }
            cursor += 1
        }
        if sentences.isEmpty {
            let named = headers.filter { !$0.isEmpty }
            if !named.isEmpty {
                sentences.append(Punctuation.terminated(named.joined(separator: ", ")))
            }
        }
        return MarkdownTable(sentences: sentences, endIndex: cursor)
    }

    private static func header(_ cell: String) -> String {
        var text = InlineCleaner.clean(cell)
        while text.hasSuffix(":") { text.removeLast() }
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func sentence(headers: [String], values: [String]) -> String? {
        var parts: [String] = []
        for (offset, value) in values.enumerated() where !value.isEmpty {
            let header = offset < headers.count ? headers[offset] : ""
            parts.append(header.isEmpty ? value : "\(header): \(value)")
        }
        guard !parts.isEmpty else { return nil }
        return Punctuation.terminated(parts.joined(separator: ", "))
    }

    static func cells(in line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|"), !row.hasSuffix("\\|") { row.removeLast() }

        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in row {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        cells.append(current)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

enum ProseCleaner {
    private static let heading = Pattern(#"^#{1,6}(?:\s+(.*?))?\s*#*\s*$"#)
    private static let bullet = Pattern(#"^[-*+•]\s+(?:\[[ xX]\]\s+)?(.*)$"#)
    private static let numbered = Pattern(#"^(\d{1,3})[.)]\s+(.*)$"#)
    private static let rule = Pattern(#"^(?:(?:[-*_]\s*){3,}|=+)$"#)

    static func paragraphs(from lines: [String]) -> [String] {
        var output: [String] = []
        var buffer: [String] = []
        var bufferIsBlock = false

        func flush() {
            defer {
                buffer.removeAll()
                bufferIsBlock = false
            }
            guard !buffer.isEmpty else { return }
            let cleaned = InlineCleaner.clean(joinWrapped(buffer))
            guard cleaned.containsSpeakableCharacters else { return }
            output.append(bufferIsBlock ? Punctuation.terminated(cleaned) : cleaned)
        }

        for raw in lines {
            let line = stripQuoteMarkers(raw.trimmingCharacters(in: .whitespaces))
            if line.isEmpty || rule.matches(line) {
                flush()
                continue
            }
            if let groups = heading.groups(in: line) {
                flush()
                buffer = [groups[0] ?? ""]
                bufferIsBlock = true
                flush()
                continue
            }
            if let groups = bullet.groups(in: line) {
                flush()
                buffer = [groups[0] ?? ""]
                bufferIsBlock = true
                continue
            }
            if let groups = numbered.groups(in: line), let number = groups[0] {
                flush()
                buffer = ["\(number): \(groups[1] ?? "")"]
                bufferIsBlock = true
                continue
            }
            buffer.append(line)
        }
        flush()
        return output
    }

    private static func stripQuoteMarkers(_ line: String) -> String {
        var rest = Substring(line)
        while rest.first == ">" {
            rest = rest.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
        }
        return String(rest)
    }

    static func joinWrapped(_ lines: [String]) -> String {
        var result = ""
        for line in lines {
            if result.isEmpty {
                result = line
                continue
            }
            if result.hasSuffix("-"),
               let previous = result.dropLast().last, previous.isLetter,
               let next = line.first, next.isLowercase {
                result.removeLast()
                result += line
            } else {
                result += " " + line
            }
        }
        return result
    }
}

enum InlineCleaner {
    private static let escapes = Pattern(#"\\([\\`*_{}\[\]()#+\-.!|>~])"#)
    private static let lineBreakTag = Pattern(#"<br\s*/?>"#, caseInsensitive: true)
    private static let image = Pattern(#"!\[([^\]]*)\]\([^)]*\)"#)
    private static let link = Pattern(#"\[([^\]]+)\]\([^)]*\)"#)
    private static let referenceLink = Pattern(#"\[([^\]]+)\]\[[^\]]*\]"#)
    private static let autolink = Pattern(#"<((?:https?|ftp)://[^>\s]+)>"#, caseInsensitive: true)
    private static let htmlTag = Pattern(#"</?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>]*)?/?>"#)
    private static let inlineCode = Pattern(#"(`+)(.+?)\1"#)
    private static let bareURL = Pattern(#"(?:\b(?:https?|ftp)://|\bwww\.)[^\s<>"'\[\](){}]+"#, caseInsensitive: true)
    private static let bold = Pattern(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    private static let strike = Pattern(#"~~(?=\S)(.+?)(?<=\S)~~"#)
    private static let starItalic = Pattern(#"(?<![\p{L}\p{N}*])\*(?=\S)(.+?)(?<=\S)\*(?![\p{L}\p{N}*])"#)
    private static let underscoreItalic = Pattern(#"(?<![\p{L}\p{N}_])_(?=\S)(.+?)(?<=\S)_(?![\p{L}\p{N}_])"#)
    private static let strayStars = Pattern(#"\*+"#)
    private static let hashes = Pattern(#"(?<![\p{L}\p{N}&])#+"#)
    private static let pipes = Pattern(#"\s*\|\s*"#)
    private static let arrow = Pattern(#"\s*(?:-{1,2}>|→|⟶)\s*"#)
    private static let ampersand = Pattern(#"\s*&\s*"#)
    private static let forExample = Pattern(#"\b([Ee])\.\s?[Gg]\."#)
    private static let thatIs = Pattern(#"\b([Ii])\.\s?[Ee]\."#)
    private static let etCetera = Pattern(#"\b([Ee])tc\."#)
    private static let versus = Pattern(#"\b[Vv]s\.?(?=\s)"#)
    private static let spaces = Pattern("[ \\t\\u00A0]+")
    private static let spaceBeforePunctuation = Pattern(#" +([,.;:!?])"#)
    private static let repeatedCommas = Pattern(#",(?:\s*,)+"#)
    private static let edgeCommas = Pattern(#"^[\s,]+|[\s,]+$"#)

    private static let entities: [(String, String)] = [
        ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
        ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&"),
    ]

    static func clean(_ input: String) -> String {
        var text = input
        text = escapes.replace(in: text, with: "$1")
        text = lineBreakTag.replace(in: text, with: " ")
        text = image.replace(in: text, with: "$1")
        text = link.replace(in: text, with: "$1")
        text = referenceLink.replace(in: text, with: "$1")
        text = autolink.replace(in: text) { match in URLShortener.domain(of: match[1] ?? "") }
        text = htmlTag.replace(in: text, with: " ")
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = inlineCode.replace(in: text, with: "$2")
        text = bareURL.replace(in: text) { match in URLShortener.shorten(match[0] ?? "") }
        text = bold.replace(in: text, with: "$2")
        text = strike.replace(in: text, with: "$1")
        text = starItalic.replace(in: text, with: "$1")
        text = underscoreItalic.replace(in: text, with: "$1")
        text = strayStars.replace(in: text, with: "")
        text = hashes.replace(in: text, with: "")
        text = pipes.replace(in: text, with: ", ")
        text = arrow.replace(in: text, with: " to ")
        text = ampersand.replace(in: text, with: " and ")
        text = forExample.replace(in: text) { match in match[1] == "E" ? "For example" : "for example" }
        text = thatIs.replace(in: text) { match in match[1] == "I" ? "That is" : "that is" }
        text = etCetera.replace(in: text) { match in
            let phrase = match[1] == "E" ? "Et cetera" : "et cetera"
            return match.endsSentence ? phrase + "." : phrase
        }
        text = versus.replace(in: text, with: "versus")
        text = spaces.replace(in: text, with: " ")
        text = spaceBeforePunctuation.replace(in: text, with: "$1")
        text = repeatedCommas.replace(in: text, with: ",")
        text = edgeCommas.replace(in: text, with: "")
        return text.trimmingCharacters(in: .whitespaces)
    }
}

enum URLShortener {
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?'\"")

    static func shorten(_ url: String) -> String {
        var core = Substring(url)
        var trailing = ""
        while let last = core.unicodeScalars.last, trailingPunctuation.contains(last) {
            trailing = String(core.removeLast()) + trailing
        }
        return domain(of: String(core)) + trailing
    }

    static func domain(of url: String) -> String {
        var candidate = url
        if candidate.lowercased().hasPrefix("www.") {
            candidate = "http://" + candidate
        }
        var host = URLComponents(string: candidate)?.host ?? ""
        if host.isEmpty {
            let withoutScheme = candidate.range(of: "://").map { String(candidate[$0.upperBound...]) } ?? candidate
            host = String(withoutScheme.prefix(while: { $0 != "/" && $0 != "?" && $0 != "#" && $0 != ":" }))
        }
        host = host.lowercased()
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
    }
}

enum Punctuation {
    private static let terminators: Set<Character> = [".", "!", "?", "…", "؟", "۔", "。", "！", "？"]

    static func terminated(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return trimmed }
        if terminators.contains(last) { return trimmed }
        if last == ":" || last == ";" || last == "," {
            return String(trimmed.dropLast()) + "."
        }
        return trimmed + "."
    }
}

extension String {
    var containsSpeakableCharacters: Bool {
        unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }
}
