import Foundation

public struct Pronunciation: Codable, Equatable, Hashable, Sendable {
    public var written: String
    public var spoken: String

    public init(written: String, spoken: String) {
        self.written = written
        self.spoken = spoken
    }

    public var isUsable: Bool {
        !written.trimmingCharacters(in: .whitespaces).isEmpty
            && !spoken.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

public enum CodeBlockMode: String, CaseIterable, Sendable {
    case skip
    case describe
    case read
}

struct TechnicalSpeech {
    let speaksTechnicalTerms: Bool

    private let customPattern: Pattern?
    private let customLookup: [String: String]

    init(speaksTechnicalTerms: Bool, pronunciations: [Pronunciation]) {
        self.speaksTechnicalTerms = speaksTechnicalTerms
        var lookup: [String: String] = [:]
        for entry in pronunciations where entry.isUsable {
            lookup[entry.written.trimmingCharacters(in: .whitespaces).lowercased()] = entry.spoken.trimmingCharacters(in: .whitespaces)
        }
        customLookup = lookup
        customPattern = lookup.isEmpty ? nil : Self.wordListPattern(Array(lookup.keys), caseInsensitive: true)
    }

    func prose(_ input: String) -> String {
        var text = applyCustom(input)
        guard speaksTechnicalTerms else { return text }
        text = Self.applyLexicon(text)
        text = Self.proseOperator.replace(in: text) { match in
            " \(Self.proseOperatorWords[match[1] ?? ""] ?? "") "
        }
        text = Self.version.replace(in: text, with: "version $1")
        text = Self.issueNumber.replace(in: text, with: "number $1")
        text = Self.functionCall.replace(in: text) { match in Self.speakDotted(match[1] ?? "") }
        text = Self.flag.replace(in: text) { match in
            (match[1] ?? "") + Self.speakFlag(dashes: match[2] ?? "", name: match[3] ?? "")
        }
        text = Self.dotfile.replace(in: text) { match in "dot " + (match[1] ?? "") }
        text = Self.path(code: false).replace(in: text) { match in Self.speakPath(match[0] ?? "", code: false) }
        text = Self.fileName(code: false).replace(in: text) { match in
            Self.speakFile(name: match[1] ?? "", extension: match[2] ?? "")
        }
        text = Self.snakeCase.replace(in: text) { match in Self.identifier(match[1] ?? "", keepCase: false) }
        text = Self.camelCase.replace(in: text) { match in Self.identifier(match[1] ?? "", keepCase: false) }
        text = Self.pascalCase.replace(in: text) { match in Self.identifier(match[1] ?? "", keepCase: true) }
        text = Self.acronymWord.replace(in: text) { match in Self.identifier(match[1] ?? "", keepCase: true) }
        text = Self.acronym.replace(in: text) { match in Self.spellAcronym(match[1] ?? "", plural: match[2] ?? "") }
        return text
    }

    func code(_ input: String) -> String {
        guard speaksTechnicalTerms else { return applyCustom(input) }
        var text = Self.urlInCode.replace(in: input) { match in " " + URLShortener.shorten(match[0] ?? "") + " " }
        text = Self.blockComment.replace(in: text) { match in Self.comment(match[1] ?? "") }
        text = Self.lineComment.replace(in: text) { match in Self.comment(match[1] ?? "") }
        text = Self.stringLiteral.replace(in: text) { match in " " + (match[2] ?? "") + " " }
        text = applyCustom(text)
        text = Self.applyLexicon(text)
        text = Self.digitGrouping.replace(in: text, with: "$1")
        text = Self.flag.replace(in: text) { match in
            (match[1] ?? "") + Self.speakFlag(dashes: match[2] ?? "", name: match[3] ?? "")
        }
        text = Self.dotfile.replace(in: text) { match in "dot " + (match[1] ?? "") }
        text = Self.path(code: true).replace(in: text) { match in " " + Self.speakPath(match[0] ?? "", code: true) + " " }
        text = Self.fileName(code: true).replace(in: text) { match in
            Self.speakFile(name: match[1] ?? "", extension: match[2] ?? "")
        }
        for (symbol, words) in Self.codeOperators {
            text = text.replacingOccurrences(of: symbol, with: " \(words) ")
        }
        text = Self.spacedOperator.replace(in: text) { match in
            " \(Self.spacedOperatorWords[match[1] ?? ""] ?? "") "
        }
        text = Self.assignment.replace(in: text, with: " equals ")
        text = Self.negation.replace(in: text, with: " not ")
        text = Self.memberAccess.replace(in: text, with: " dot ")
        text = Self.decorator.replace(in: text, with: " at ")
        text = Self.homePath.replace(in: text, with: " home ")
        text = Self.leftoverSymbols.replace(in: text, with: " ")
        text = Self.wordToken.replace(in: text) { match in Self.identifier(match[0] ?? "", keepCase: false) }
        text = Self.acronym.replace(in: text) { match in Self.spellAcronym(match[1] ?? "", plural: match[2] ?? "") }
        text = Self.spaces.replace(in: text, with: " ")
        text = Self.spaceBeforeComma.replace(in: text, with: ",")
        text = Self.repeatedCommas.replace(in: text, with: ",")
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
    }

    func codeLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#!") || !trimmed.containsSpeakableCharacters { return "" }
        if speaksTechnicalTerms, trimmed.hasPrefix("# ") || trimmed == "#" {
            let comment = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            return comment.isEmpty ? "" : "comment, " + applyCustom(comment)
        }
        let withoutPrompt = trimmed.hasPrefix("$ ") ? String(trimmed.dropFirst(2)) : trimmed
        return code(withoutPrompt)
    }

    private static func comment(_ body: String) -> String {
        body.containsSpeakableCharacters ? " comment, \(body) " : " "
    }

    static func describe(lines: [String], language: String?) -> String {
        let count = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let length = count == 1 ? "1 line" : "\(count) lines"
        if let name = language.flatMap(languageName) {
            return "\(name) code block, \(length), skipped."
        }
        return "Code block, \(length), skipped."
    }

    private func applyCustom(_ text: String) -> String {
        guard let customPattern else { return text }
        return customPattern.replace(in: text) { match in
            customLookup[(match[0] ?? "").lowercased()] ?? (match[0] ?? "")
        }
    }

    private static func applyLexicon(_ text: String) -> String {
        lexiconPattern.replace(in: text) { match in lexicon[match[0] ?? ""] ?? (match[0] ?? "") }
    }

    static func identifier(_ token: String, keepCase: Bool) -> String {
        if token.allSatisfy({ $0.isNumber || $0 == "_" }) {
            return token.replacingOccurrences(of: "_", with: "")
        }
        let spaced = identifierBoundary.replace(in: token, with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let parts = spaced.split(separator: " ").map(String.init)
        if parts.count <= 1 {
            if let known = lexicon[token] { return known }
            if token.count >= 2, token.allSatisfy({ $0.isUppercase }) {
                return spellAcronym(token, plural: "")
            }
            return token
        }
        let spoken = parts.map { part -> String in
            if let known = lexicon[part] { return known }
            if part.count >= 2, part.allSatisfy({ $0.isUppercase }) {
                let spelled = spellAcronym(part, plural: "")
                return spelled == part && !keepCase ? part.lowercased() : spelled
            }
            return keepCase ? part : part.lowercased()
        }
        return spoken.joined(separator: " ")
    }

    static func spellAcronym(_ letters: String, plural: String) -> String {
        let upper = letters.uppercased()
        if let known = lexicon[letters + plural] { return known }
        let vowels: Set<Character> = ["A", "E", "I", "O", "U", "Y"]
        let roman: Set<Character> = ["I", "V", "X", "L", "C", "D", "M"]
        guard upper.count >= 2,
              !upper.contains(where: vowels.contains),
              !upper.allSatisfy(roman.contains),
              upper.allSatisfy(\.isLetter)
        else { return letters + plural }
        return upper.map(String.init).joined(separator: " ") + plural
    }

    private static func speakDotted(_ chain: String) -> String {
        chain.split(separator: ".").map { identifier(String($0), keepCase: false) }.joined(separator: " dot ")
    }

    private static func speakFlag(dashes: String, name: String) -> String {
        let words = identifier(name, keepCase: false)
        return dashes == "--" ? "dash dash \(words)" : "dash \(words)"
    }

    private static func speakFile(name: String, extension ext: String) -> String {
        let spokenName = name.split(separator: ".").map { identifier(String($0), keepCase: true) }.joined(separator: " dot ")
        let spokenExtension = fileExtensions[ext.lowercased()] ?? ext
        return "\(spokenName) dot \(spokenExtension)"
    }

    private static func speakPath(_ raw: String, code: Bool) -> String {
        var path = Substring(raw)
        var trailing = ""
        while let last = path.last, ".,;:".contains(last) {
            trailing = String(path.removeLast()) + trailing
        }
        var words: [String] = []
        if path.hasPrefix("/") { words.append("slash") }
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        for (offset, component) in components.enumerated() {
            if offset > 0 { words.append("slash") }
            switch component {
            case "~": words.append("home")
            case ".": words.append("dot")
            case "..": words.append("dot dot")
            case let hidden where hidden.hasPrefix(".") && hidden.count > 1:
                words.append("dot " + identifier(String(hidden.dropFirst()), keepCase: true))
            default:
                let piece = String(component)
                if let match = fileName(code: code).groups(in: piece), let name = match[0], let ext = match[1],
                   name.count + ext.count + 1 == piece.count {
                    words.append(speakFile(name: name, extension: ext))
                } else {
                    words.append(identifier(piece, keepCase: true))
                }
            }
        }
        if raw.hasSuffix("/"), !path.isEmpty, path != "/" { words.append("slash") }
        return words.joined(separator: " ") + trailing
    }

    private static func languageName(_ tag: String) -> String? {
        let names: [String: String] = [
            "swift": "Swift", "js": "JavaScript", "javascript": "JavaScript", "jsx": "JavaScript",
            "ts": "TypeScript", "typescript": "TypeScript", "tsx": "TypeScript",
            "py": "Python", "python": "Python", "rb": "Ruby", "ruby": "Ruby", "go": "Go", "golang": "Go",
            "rs": "Rust", "rust": "Rust", "java": "Java", "kt": "Kotlin", "kotlin": "Kotlin",
            "c": "C", "cpp": "C plus plus", "c++": "C plus plus", "cs": "C sharp", "csharp": "C sharp",
            "php": "P H P", "sh": "Shell", "bash": "Shell", "zsh": "Shell", "shell": "Shell", "console": "Shell",
            "sql": "S Q L", "html": "H T M L", "css": "C S S", "scss": "S C S S", "json": "Jason",
            "yaml": "Yamel", "yml": "Yamel", "toml": "Tommel", "xml": "X M L", "md": "Markdown",
            "markdown": "Markdown", "diff": "Diff", "dockerfile": "Dockerfile", "makefile": "Makefile",
            "graphql": "Graph Q L", "lua": "Lua", "dart": "Dart", "r": "R", "objc": "Objective C",
            "vue": "Vue", "svelte": "Svelte", "powershell": "PowerShell", "ps1": "PowerShell",
        ]
        let key = tag.lowercased()
        if let name = names[key] { return name }
        guard key.count >= 2, key.allSatisfy({ $0.isLetter }) else { return nil }
        return key.prefix(1).uppercased() + key.dropFirst()
    }

    private static func wordListPattern(_ words: [String], caseInsensitive: Bool) -> Pattern {
        let alternatives = words
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        return Pattern(#"(?<![\p{L}\p{N}_])(?:"# + alternatives + #")(?![\p{L}\p{N}_])"#, caseInsensitive: caseInsensitive)
    }

    static let lexicon: [String: String] = [
        "API": "A P I", "APIs": "A P Is", "AWS": "A W S", "UI": "U I", "UX": "U X", "CLI": "C L I",
        "CI": "C I", "CI/CD": "C I C D", "IDE": "I D E", "URL": "U R L", "URLs": "U R Ls", "URI": "U R I",
        "ID": "I D", "IDs": "I Ds", "IO": "I O", "I/O": "I O", "OS": "O S", "AI": "A I", "GPU": "G P U",
        "CPU": "C P U", "IAM": "I A M", "SSO": "S S O", "OSS": "O S S", "SEO": "S E O", "FAQ": "F A Q",
        "TCP/IP": "T C P I P", "UTF-8": "U T F 8", "UUID": "U U I D", "IPv4": "I P v 4", "IPv6": "I P v 6",
        "JSON": "Jason", "YAML": "yamel", "TOML": "tommel", "GUI": "gooey", "ASCII": "askey",
        "OAuth": "oh auth", "OAuth2": "oh auth 2", "SaaS": "sass", "CRUD": "crud", "WIP": "W I P",
        "macOS": "mac O S", "iOS": "eye O S", "iPadOS": "eye pad O S", "watchOS": "watch O S",
        "tvOS": "T V O S", "visionOS": "vision O S", "GitHub": "git hub", "GitLab": "git lab",
        "npm": "N P M", "pnpm": "P N P M", "npx": "N P X", "nginx": "engine x", "Nginx": "engine x",
        "kubectl": "kube control", "k8s": "kubernetes", "K8s": "kubernetes", "i18n": "internationalization",
        "a11y": "accessibility", "sudo": "sue doo", "regex": "rej ex", "stdin": "standard in",
        "stdout": "standard out", "stderr": "standard error", "async": "a sync", "enum": "ee num",
        "localhost": "local host", "README": "read me", "TODO": "to do", "FIXME": "fix me",
        "Node.js": "node J S", "Next.js": "next J S", "Vue.js": "view J S", "Nuxt.js": "nuxt J S",
        "Three.js": "three J S", "D3.js": "D 3 J S", "Express.js": "express J S", ".NET": "dot net",
        "C#": "C sharp", "F#": "F sharp", "C++": "C plus plus", "PostgreSQL": "postgres Q L",
        "MySQL": "my S Q L", "SQLite": "S Q lite", "NoSQL": "no S Q L", "PyPI": "pie P I",
        "PyTorch": "pie torch", "NumPy": "num pie", "SciPy": "sigh pie", "ChatGPT": "chat G P T",
        "OpenAI": "open A I", "VS Code": "V S code", "Xcode": "X code", "WebKit": "web kit",
        "SwiftUI": "swift U I", "UIKit": "U I kit", "AppKit": "app kit", "jQuery": "jay query",
    ]

    private static let lexiconPattern = wordListPattern(Array(lexicon.keys), caseInsensitive: false)

    private static let proseExtensions = [
        "swift", "ts", "tsx", "js", "jsx", "mjs", "cjs", "py", "rb", "rs", "go", "java", "kt", "php",
        "cs", "cpp", "hpp", "md", "mdx", "json", "yml", "yaml", "toml", "xml", "html", "css", "scss",
        "sql", "sh", "zsh", "bash", "txt", "csv", "log", "lock", "plist", "pdf", "png", "jpg", "jpeg",
        "gif", "svg", "webp", "mp3", "mp4", "mov", "wav", "zip", "tar", "gz", "dmg", "app", "exe",
        "dll", "vue", "svelte", "dart", "lua", "ipynb", "xib", "storyboard", "xcodeproj", "gradle",
    ]

    private static let fileExtensions: [String: String] = [
        "swift": "swift", "ts": "T S", "tsx": "T S X", "js": "J S", "jsx": "J S X", "mjs": "M J S",
        "cjs": "C J S", "py": "pie", "rb": "R B", "rs": "R S", "go": "go", "java": "java", "kt": "K T",
        "php": "P H P", "cs": "C S", "cpp": "C P P", "hpp": "H P P", "c": "C", "h": "H", "md": "M D",
        "mdx": "M D X", "json": "Jason", "yml": "yamel", "yaml": "yamel", "toml": "tommel", "xml": "X M L",
        "html": "H T M L", "css": "C S S", "scss": "S C S S", "sql": "S Q L", "sh": "S H", "zsh": "Z S H",
        "bash": "bash", "txt": "text", "csv": "C S V", "log": "log", "lock": "lock", "plist": "P list",
        "pdf": "P D F", "png": "P N G", "jpg": "J P G", "jpeg": "J peg", "gif": "gif", "svg": "S V G",
        "webp": "web P", "mp3": "M P 3", "mp4": "M P 4", "mov": "mov", "wav": "wave", "zip": "zip",
        "tar": "tar", "gz": "G Z", "dmg": "D M G", "app": "app", "exe": "E X E", "dll": "D L L",
        "vue": "view", "svelte": "svelte", "dart": "dart", "lua": "lua", "ipynb": "notebook",
        "xib": "X I B", "storyboard": "storyboard", "xcodeproj": "X code project", "gradle": "gradle",
    ]

    private static func fileName(code: Bool) -> Pattern {
        code ? codeFileName : proseFileName
    }

    private static func path(code: Bool) -> Pattern {
        code ? codePath : prosePath
    }

    private static func extensionAlternatives(code: Bool) -> String {
        (proseExtensions + (code ? ["c", "h"] : []))
            .sorted { $0.count > $1.count }
            .joined(separator: "|")
    }

    private static let proseFileName = Pattern(
        #"(?<![\p{L}\p{N}_./\-@])([A-Za-z0-9_][A-Za-z0-9_\-]*(?:\.[A-Za-z0-9_\-]+)*)\.("# + extensionAlternatives(code: false) + #")(?![\p{L}\p{N}_])"#,
        caseInsensitive: true
    )
    private static let codeFileName = Pattern(
        #"(?<![\p{L}\p{N}_./\-@])([A-Za-z0-9_][A-Za-z0-9_\-]*(?:\.[A-Za-z0-9_\-]+)*)\.("# + extensionAlternatives(code: true) + #")(?![\p{L}\p{N}_])"#,
        caseInsensitive: true
    )
    private static let prosePath = Pattern(
        #"(?<![\p{L}\p{N}_/.:~])(?:(?:~|\.{1,2})?/[A-Za-z0-9_.@\-]+(?:/[A-Za-z0-9_.@\-]+)*/?|[A-Za-z0-9_@\-]+(?:/[A-Za-z0-9_.@\-]+)*/[A-Za-z0-9_\-.]+\.(?:"# + extensionAlternatives(code: false) + #"))(?![\p{L}\p{N}_/])"#
    )
    private static let codePath = Pattern(
        #"(?<![\p{L}\p{N}_/.:~])(?:(?:~|\.{1,2})?/[A-Za-z0-9_.@\-]+(?:/[A-Za-z0-9_.@\-]+)*/?|[A-Za-z0-9_@\-.]+(?:/[A-Za-z0-9_.@\-]+)+/?)(?![\p{L}\p{N}_/])"#
    )

    private static let proseOperatorWords: [String: String] = [
        "===": "strictly equals", "!==": "is strictly not equal to", "==": "equals", "!=": "is not equal to",
        "<=": "is less than or equal to", ">=": "is greater than or equal to", "&&": "and", "||": "or",
        "=>": "to",
    ]
    private static let proseOperator = Pattern(#"(?<=\s)(===|!==|==|!=|<=|>=|&&|\|\||=>)(?=\s)"#)

    private static let codeOperators: [(String, String)] = [
        ("===", "strictly equals"), ("!==", "strictly not equal to"), ("==", "equals"), ("!=", "not equal to"),
        ("<=", "less than or equal to"), (">=", "greater than or equal to"), ("=>", "arrow"), ("->", "arrow"),
        ("&&", "and"), ("||", "or"), ("+=", "plus equals"), ("-=", "minus equals"), ("*=", "times equals"),
        ("/=", "divided by equals"), ("++", "plus plus"), ("--", "minus minus"), ("??", "or else"),
        ("?.", " dot "), ("::", " "),
    ]
    private static let spacedOperatorWords: [String: String] = [
        "+": "plus", "-": "minus", "*": "times", "/": "divided by", "%": "mod", "<": "less than",
        ">": "greater than", "|": "pipe", "&": "and",
    ]
    private static let spacedOperator = Pattern(#"(?<=\s)([+\-*/%<>|&])(?=\s)"#)
    private static let assignment = Pattern(#"(?<![=!<>+\-*/%])=(?!=)"#)
    private static let negation = Pattern(#"!(?=[\p{L}(_])"#)
    private static let memberAccess = Pattern(#"(?<=[\p{L}\p{N}_)\]}])\s*\.(?=[\p{L}_])"#)
    private static let decorator = Pattern(#"(?<![\p{L}\p{N}_])@(?=[\p{L}_])"#)
    private static let homePath = Pattern(#"(?<![\p{L}\p{N}_])~(?=\s|$)"#)
    private static let leftoverSymbols = Pattern(#"[`$#\\^~*|&?:!;"'(){}\[\]<>]"#)
    private static let wordToken = Pattern(#"[A-Za-z_][A-Za-z0-9_\-]*[A-Za-z0-9]|[A-Za-z]"#)
    private static let digitGrouping = Pattern(#"(\d)_(?=\d)"#)
    private static let blockComment = Pattern(#"/\*\s*(.*?)\s*\*/"#)
    private static let lineComment = Pattern(#"(?<![:/])//\s*(.*)$"#)
    private static let stringLiteral = Pattern(#"(["'])((?:(?!\1).)*)\1"#)
    private static let urlInCode = Pattern(#"(?:\b(?:https?|ftp)://|\bwww\.)[^\s<>"'\[\](){}]+"#, caseInsensitive: true)
    private static let spaces = Pattern(#"\s+"#)
    private static let spaceBeforeComma = Pattern(#"\s+,"#)
    private static let repeatedCommas = Pattern(#",(?:\s*,)+"#)

    private static let version = Pattern(#"(?<![\p{L}\p{N}_])v(\d+(?:\.\d+){1,3})(?![\p{L}\p{N}_])"#)
    private static let issueNumber = Pattern(#"(?<![\p{L}\p{N}_&#])#(\d+)(?![\p{L}\p{N}_])"#)
    private static let functionCall = Pattern(#"(?<![\p{L}\p{N}_.])([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)\(\)"#)
    private static let flag = Pattern(#"(^|[\s(\[])(--?)([A-Za-z][A-Za-z0-9\-]*)"#)
    private static let dotfile = Pattern(#"(?<![\p{L}\p{N}_/.])\.(env|gitignore|zshrc|bashrc|npmrc|editorconfig|prettierrc|eslintrc|gitattributes)(?![\p{L}\p{N}_])"#)
    private static let snakeCase = Pattern(#"(?<![\p{L}\p{N}_])([A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)+)(?![\p{L}\p{N}_])"#)
    private static let camelCase = Pattern(#"(?<![\p{L}\p{N}_])([a-z]{2,}[0-9]*(?:[A-Z][a-z0-9]*)+)(?![\p{L}\p{N}_])"#)
    private static let pascalCase = Pattern(#"(?<![\p{L}\p{N}_])([A-Z][a-z]{2,}(?:[A-Z][a-z]{2,})+)(?![\p{L}\p{N}_])"#)
    private static let acronymWord = Pattern(#"(?<![\p{L}\p{N}_])([A-Z]{2,}(?:[A-Z][a-z]{2,})+)(?![\p{L}\p{N}_])"#)
    private static let acronym = Pattern(#"(?<![\p{L}\p{N}_])([A-Z]{2,6})(s?)(?![\p{L}\p{N}_])"#)
    private static let identifierBoundary = Pattern(#"(?<=[a-z0-9])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])|(?<=[A-Za-z])(?=[0-9])|(?<=[0-9])(?=[A-Za-z])"#)
}
