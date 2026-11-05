import Testing
@testable import ReadoutCore

@Suite("Markdown symbols")
struct MarkdownSymbolTests {
    @Test func headingsBecomeTheirOwnSentence() {
        #expect(TextCleaner.clean("# Getting started\nInstall the app") == "Getting started.\n\nInstall the app")
        #expect(TextCleaner.clean("### Closing hashes ###") == "Closing hashes.")
        #expect(TextCleaner.clean("Heading?\n##") == "Heading?")
    }

    @Test func hashtagWithoutSpaceIsNotAHeading() {
        #expect(TextCleaner.clean("#hashtag trending") == "hashtag trending")
    }

    @Test func emphasisMarkersAreRemoved() {
        let input = "This is **bold**, *italic*, __strong__, _soft_ and ~~struck~~."
        #expect(TextCleaner.clean(input) == "This is bold, italic, strong, soft and struck.")
    }

    @Test func nestedEmphasis() {
        #expect(TextCleaner.clean("***very*** important") == "very important")
    }

    @Test func underscoresInsideIdentifiersSurvive() {
        #expect(TextCleaner.clean("Call snake_case_name now") == "Call snake_case_name now")
    }

    @Test func inlineCodeKeepsItsContent() {
        #expect(TextCleaner.clean("Run `swift build` then ``a `b` c``") == "Run swift build then a `b` c")
    }

    @Test func tripleBackticksOnOneLineAreInlineCode() {
        #expect(TextCleaner.clean("```inline```") == "inline")
    }

    @Test func blockquotesLoseTheirMarkers() {
        #expect(TextCleaner.clean("> Quoted line\n> continues here") == "Quoted line continues here")
        #expect(TextCleaner.clean("> > Nested quote") == "Nested quote")
        #expect(TextCleaner.clean("> First\n>\n> Second") == "First\n\nSecond")
    }

    @Test func bulletListsBecomeSentences() {
        #expect(TextCleaner.clean("- Apples\n* Pears\n+ Plums") == "Apples.\n\nPears.\n\nPlums.")
    }

    @Test func listItemContinuationLinesJoin() {
        #expect(TextCleaner.clean("- First item\n  wraps here\n- Second") == "First item wraps here.\n\nSecond.")
    }

    @Test func taskListCheckboxesAreRemoved() {
        #expect(TextCleaner.clean("- [x] Done\n- [ ] Todo") == "Done.\n\nTodo.")
    }

    @Test func numberedListsKeepTheirNumbers() {
        #expect(TextCleaner.clean("1. Install\n2) Launch") == "1: Install.\n\n2: Launch.")
    }

    @Test func horizontalRulesDisappear() {
        #expect(TextCleaner.clean("Above\n\n---\n\nBelow\n***\n___") == "Above\n\nBelow")
    }

    @Test func setextUnderlinesDisappear() {
        #expect(TextCleaner.clean("Title\n=====\nBody") == "Title\n\nBody")
    }

    @Test func strayPipesBecomeCommas() {
        #expect(TextCleaner.clean("Home | About | Contact") == "Home, About, Contact")
    }

    @Test func imagesReadTheirAltText() {
        #expect(TextCleaner.clean("![A red bicycle](bike.png) is shown") == "A red bicycle is shown")
    }

    @Test func linksReadTheirText() {
        #expect(TextCleaner.clean("Read [the docs](https://developer.apple.com/documentation) first") == "Read the docs first")
        #expect(TextCleaner.clean("See [this page][1].") == "See this page.")
    }

    @Test func htmlTagsAndEntitiesAreRemoved() {
        #expect(TextCleaner.clean("Line<br>break and <b>bold</b>") == "Line break and bold")
        #expect(TextCleaner.clean("Tom &amp; Jerry &lt;3") == "Tom and Jerry <3")
    }

    @Test func backslashEscapesAreRemoved() {
        #expect(TextCleaner.clean(#"Price \*not\* final"#) == "Price not final")
    }

    @Test func onlySymbolsProducesNothing() {
        #expect(TextCleaner.clean("***\n\n| |\n\n#") == "")
    }
}

@Suite("Tables")
struct TableTests {
    @Test func tableRowsBecomeColumnValueSentences() {
        let input = """
        | Name | Age |
        |------|-----|
        | Alice | 30 |
        | Bob | 25 |
        """
        #expect(TextCleaner.clean(input) == "Name: Alice, Age: 30.\n\nName: Bob, Age: 25.")
    }

    @Test func tablesWithoutOuterPipesAndWithAlignment() {
        let input = "Name | Role\n:--- | ---:\nAli | Developer"
        #expect(TextCleaner.clean(input) == "Name: Ali, Role: Developer.")
    }

    @Test func emptyCellsAreSkipped() {
        let input = "| A | B | C |\n|---|---|---|\n| x |  | z |"
        #expect(TextCleaner.clean(input) == "A: x, C: z.")
    }

    @Test func cellMarkdownIsCleaned() {
        let input = "| **Key** | Value |\n|---|---|\n| `timeout` | [30s](https://x.io) |"
        #expect(TextCleaner.clean(input) == "Key: timeout, Value: 30s.")
    }

    @Test func extraCellsWithoutHeadersAreStillRead() {
        let input = "| A |\n|---|\n| one | two |"
        #expect(TextCleaner.clean(input) == "A: one, two.")
    }

    @Test func headerOnlyTableReadsColumnNames() {
        #expect(TextCleaner.clean("| Plan | Price |\n|---|---|") == "Plan, Price.")
    }

    @Test func escapedPipesStayInsideACell() {
        let input = #"| Operator | Meaning |"# + "\n|---|---|\n" + #"| a \| b | or |"#
        #expect(TextCleaner.clean(input) == "Operator: a, b, Meaning: or.")
    }

    @Test func tableEndsAtBlankLine() {
        let input = "| A | B |\n|---|---|\n| 1 | 2 |\n\nAfter the table."
        #expect(TextCleaner.clean(input) == "A: 1, B: 2.\n\nAfter the table.")
    }

    @Test func textAroundTableIsKept() {
        let input = "Results:\n| Test | Result |\n|---|---|\n| Login | Pass |\nAll good."
        #expect(TextCleaner.clean(input) == "Results:\n\nTest: Login, Result: Pass.\n\nAll good.")
    }

    @Test func pipeTextWithoutDelimiterRowIsNotATable() {
        #expect(TextCleaner.clean("a | b\nc | d") == "a, b c, d")
    }
}

@Suite("Code blocks")
struct CodeBlockTests {
    private let sample = "Intro\n```swift\nlet value = a -> b\nprint(**value**)\n```\nOutro"

    @Test func fencedCodeIsSkippedByDefault() {
        #expect(TextCleaner.clean(sample) == "Intro\n\nCode block skipped.\n\nOutro")
    }

    @Test func codeIsReadVerbatimWhenNotSkipped() {
        let options = CleanupOptions(isEnabled: true, skipsCodeBlocks: false)
        #expect(TextCleaner.clean(sample, options: options) == "Intro\n\nlet value = a -> b\n\nprint(**value**)\n\nOutro")
    }

    @Test func tildeFencesAndLongerFences() {
        #expect(TextCleaner.clean("~~~\ncode\n~~~\nText") == "Code block skipped.\n\nText")
        #expect(TextCleaner.clean("````\n```\nnested\n```\n````\nText") == "Code block skipped.\n\nText")
    }

    @Test func unclosedFenceSkipsToTheEnd() {
        #expect(TextCleaner.clean("Before\n```\nnever closed\nstill code") == "Before\n\nCode block skipped.")
    }

    @Test func eachBlockIsAnnounced() {
        let input = "```\na\n```\nMiddle\n```\nb\n```"
        #expect(TextCleaner.clean(input) == "Code block skipped.\n\nMiddle\n\nCode block skipped.")
    }

    @Test func tableSyntaxInsideCodeIsNotATable() {
        let input = "```\n| a | b |\n|---|---|\n```"
        let options = CleanupOptions(isEnabled: true, skipsCodeBlocks: false)
        #expect(TextCleaner.clean(input, options: options) == "| a | b |\n\n|---|---|")
    }
}

@Suite("URLs")
struct URLTests {
    @Test func bareURLsBecomeTheirDomain() {
        #expect(TextCleaner.clean("See https://www.example.com/path?q=1&r=2#top for more.") == "See example.com for more.")
    }

    @Test func trailingPunctuationIsKept() {
        #expect(TextCleaner.clean("Visit https://github.com/apple/swift.") == "Visit github.com.")
        #expect(TextCleaner.clean("Is it http://localhost:8080/x?") == "Is it localhost?")
    }

    @Test func wwwWithoutScheme() {
        #expect(TextCleaner.clean("Go to www.apple.com/mac today") == "Go to apple.com today")
    }

    @Test func autolinks() {
        #expect(TextCleaner.clean("Docs: <https://swift.org/blog/post>") == "Docs: swift.org")
    }

    @Test func subdomainsAreKept() {
        #expect(TextCleaner.clean("https://docs.github.com/en/actions") == "docs.github.com")
    }

    @Test func urlsInsideParentheses() {
        #expect(TextCleaner.clean("(see https://example.org/a/b)") == "(see example.org)")
    }
}

@Suite("Symbols")
struct SymbolTests {
    @Test func ampersands() {
        #expect(TextCleaner.clean("Salt & pepper") == "Salt and pepper")
        #expect(TextCleaner.clean("R&D team") == "R and D team")
    }

    @Test func arrows() {
        #expect(TextCleaner.clean("Login -> Dashboard") == "Login to Dashboard")
        #expect(TextCleaner.clean("A→B") == "A to B")
        #expect(TextCleaner.clean("Step --> next") == "Step to next")
    }

    @Test func forExample() {
        #expect(TextCleaner.clean("Fruit, e.g. apples") == "Fruit, for example apples")
        #expect(TextCleaner.clean("E.g., this one") == "For example, this one")
        #expect(TextCleaner.clean("(e.g. pears)") == "(for example pears)")
    }

    @Test func otherAbbreviations() {
        #expect(TextCleaner.clean("Use a tool, i.e. a hammer") == "Use a tool, that is a hammer")
        #expect(TextCleaner.clean("Bring snacks, drinks, etc. Then go.") == "Bring snacks, drinks, et cetera. Then go.")
        #expect(TextCleaner.clean("Apples, pears, etc., are fruit") == "Apples, pears, et cetera, are fruit")
        #expect(TextCleaner.clean("And so on etc.") == "And so on et cetera.")
        #expect(TextCleaner.clean("Mac vs. PC") == "Mac versus PC")
    }

    @Test func hashesBeforeNumbersAreDropped() {
        #expect(TextCleaner.clean("Issue #42 in C#") == "Issue 42 in C#")
    }
}

@Suite("Wrapping and options")
struct WrappingTests {
    @Test func wrappedLinesJoinIntoOneParagraph() {
        #expect(TextCleaner.clean("This is a long\nline that wraps.") == "This is a long line that wraps.")
    }

    @Test func hyphenatedLineBreaksAreRejoined() {
        #expect(TextCleaner.clean("Accessibility infor-\nmation matters") == "Accessibility information matters")
        #expect(TextCleaner.clean("Self-\nService") == "Self- Service")
    }

    @Test func windowsLineEndings() {
        #expect(TextCleaner.clean("# One\r\nTwo\r\n\r\nThree") == "One.\n\nTwo\n\nThree")
    }

    @Test func disabledCleanupReturnsTheInput() {
        let input = "# Title\n**bold** https://example.com/x & ```"
        #expect(TextCleaner.clean(input, options: CleanupOptions(isEnabled: false)) == input)
    }

    @Test func nonLatinScripts() {
        #expect(TextCleaner.clean("## مرحبا\nیہ **اردو** ہے۔") == "مرحبا.\n\nیہ اردو ہے۔")
    }

    @Test func mixedDocument() {
        let input = """
        # Release notes

        The **new** build adds:

        - Faster sync -> 2x
        - Fixes, e.g. login

        | Platform | Status |
        | --- | --- |
        | macOS | Shipped |

        ```bash
        make release
        ```

        Details at https://example.com/notes/42.
        """
        let expected = """
        Release notes.

        The new build adds:

        Faster sync to 2x.

        Fixes, for example login.

        Platform: macOS, Status: Shipped.

        Code block skipped.

        Details at example.com.
        """
        #expect(TextCleaner.clean(input) == expected)
    }
}
