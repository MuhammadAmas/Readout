import Foundation
import Testing
@testable import ReadoutCore

private func say(_ text: String, _ options: CleanupOptions = CleanupOptions()) -> String {
    TextCleaner.clean(text, options: options)
}

@Suite("Inline code")
struct InlineCodeTests {
    @Test func functionCallsAndIdentifiers() {
        #expect(say("Call `getUserName()` first.") == "Call get user name first.")
        #expect(say("Set `user_id` and `MAX_RETRIES`.") == "Set user id and max retries.")
        #expect(say("Use `max-width` here.") == "Use max width here.")
    }

    @Test func operators() {
        #expect(say("Check `a != b` and `x == y`.") == "Check a not equal to b and x equals y.")
        #expect(say("Use `a && b || c`.") == "Use a and b or c.")
        #expect(say("Then `count += 1`.") == "Then count plus equals 1.")
        #expect(say("Write `x = 5`.") == "Write x equals 5.")
        #expect(say("Return `items.count >= 10`.") == "Return items dot count greater than or equal to 10.")
    }

    @Test func commandsAndFlags() {
        #expect(say("Run `git push --force`.") == "Run git push dash dash force.")
        #expect(say("Try `ls -la`.") == "Try ls dash la.")
        #expect(say("Run `npm install --save-dev typescript`.") == "Run N P M install dash dash save dev typescript.")
    }

    @Test func memberAccessAndClosures() {
        #expect(say("Read `user.profile.name`.") == "Read user dot profile dot name.")
        #expect(say("Use `items.filter { $0.isActive }.count`.") == "Use items dot filter 0 dot is active dot count.")
    }

    @Test func stringsAndComments() {
        #expect(say("Use `print(\"Hello there\")`.") == "Use print Hello there.")
        #expect(say("See `let a = 1 // the answer`.") == "See let a equals 1 comment, the answer.")
    }

    @Test func pathsAndFilesInCode() {
        #expect(say("Open `src/app/main.ts`.") == "Open src slash app slash main dot T S.")
        #expect(say("Edit `~/.zshrc`.") == "Edit home slash dot zshrc.")
    }

    @Test func numbersWithSeparators() {
        #expect(say("Set `limit = 1_000_000`.") == "Set limit equals 1000000.")
    }
}

@Suite("Technical terms in prose")
struct TechnicalProseTests {
    @Test func identifiersOutsideBackticks() {
        #expect(say("The telemetry stack: OpenTelemetry, ClickHouse and Grafana.") == "The telemetry stack: Open Telemetry, Click House and Grafana.")
        #expect(say("Then useEffect calls setState.") == "Then use effect calls set state.")
        #expect(say("Read user_id from the row.") == "Read user id from the row.")
        #expect(say("The HTTPServer replied.") == "The H T T P Server replied.")
    }

    @Test func filesAndPaths() {
        #expect(say("Edit src/app/main.ts and config.yaml.") == "Edit src slash app slash main dot T S and config dot yamel.")
        #expect(say("Open the .env file.") == "Open the dot env file.")
        #expect(say("Look in /usr/local/bin today.") == "Look in slash usr slash local slash bin today.")
        #expect(say("It's in ~/Library/Logs.") == "It's in home slash Library slash Logs.")
        #expect(say("Ship Readout.app now.") == "Ship Readout dot app now.")
    }

    @Test func versionsIssuesAndCalls() {
        #expect(say("Upgrade to v1.2.3 now.") == "Upgrade to version 1.2.3 now.")
        #expect(say("See issue #4512.") == "See issue number 4512.")
        #expect(say("Then call fetchData() again.") == "Then call fetch data again.")
    }

    @Test func spacedOperators() {
        #expect(say("Only if count >= 10 && ready.") == "Only if count is greater than or equal to 10 and ready.")
        #expect(say("Make sure a != b first.") == "Make sure a is not equal to b first.")
    }

    @Test func flagsInProse() {
        #expect(say("Add --force to overwrite.") == "Add dash dash force to overwrite.")
    }

    @Test func dictionaryTerms() {
        #expect(say("Our API returns JSON.") == "Our A P I returns Jason.")
        #expect(say("Use kubectl and nginx on k8s.") == "Use kube control and engine x on kubernetes.")
        #expect(say("Written in C#, C++ and Node.js.") == "Written in C sharp, C plus plus and node J S.")
        #expect(say("It runs on macOS and iOS.") == "It runs on mac O S and eye O S.")
        #expect(say("Read the README on GitHub.") == "Read the read me on git hub.")
    }

    @Test func acronymsWithoutVowelsAreSpelled() {
        #expect(say("Load it over HTTPS as HTML and CSS.") == "Load it over H T T P S as H T M L and C S S.")
        #expect(say("Send the PDFs.") == "Send the P D Fs.")
    }

    @Test func ordinaryEnglishIsUnchanged() {
        let sentences = [
            "Readout reads ordinary English sentences, like this one, exactly as written.",
            "Prices rose 3.5% in Q3; Dr. Smith met the CEO at 5 p.m. on Wi-Fi.",
            "We offer 24/7 support, 50/50 odds, and and/or choices.",
            "THIS IS A WARNING: DO NOT PRESS THE RED BUTTON.",
            "NYC is busy. The NASA team met on Monday at the UN.",
            "Louis XIV ruled; World War II ended in 1945.",
            "She said it's well-known and state-of-the-art.",
            "My iPhone and eBay account work fine.",
            "Call me at 555-0100 or email me.",
            "The score was 3-2 and the ratio was 1:4.",
        ]
        for sentence in sentences {
            #expect(say(sentence) == sentence)
        }
    }

    @Test func switchedOffLeavesTechnicalTextAlone() {
        let plain = CleanupOptions(speaksTechnicalTerms: false)
        #expect(say("Call `getUserName()` on OpenTelemetry via JSON.", plain) == "Call getUserName() on OpenTelemetry via JSON.")
    }
}

@Suite("Code blocks read aloud")
struct CodeBlockReadingTests {
    private let read = CleanupOptions(codeBlocks: .read)

    @Test func swiftBlock() {
        let block = "```swift\n// Load the user\nlet user = try await api.fetchUser(id: userID)\nif user.isAdmin && !user.isBlocked {\n    print(\"Welcome\")\n}\n```"
        #expect(say(block, read) == """
        comment, Load the user

        let user equals try await api dot fetch user id user I D

        if user dot is admin and not user dot is blocked

        print Welcome
        """)
    }

    @Test func shellBlock() {
        let block = "```bash\n#!/bin/bash\n# Install deps\n$ npm install --save-dev typescript\n```"
        #expect(say(block, read) == "comment, Install deps\n\nN P M install dash dash save dev typescript")
    }

    @Test func symbolOnlyLinesAreSilent() {
        #expect(say("```\n}\n// -----\n|---|\nend\n```", read) == "end")
    }
}

@Suite("Custom pronunciations")
struct PronunciationTests {
    @Test func replacesWholeWordsIgnoringCapitals() {
        let options = CleanupOptions(pronunciations: [
            Pronunciation(written: "Acasia", spoken: "uh kay sha"),
            Pronunciation(written: "GroveOS", spoken: "grove O S"),
        ])
        #expect(say("Acasia ships GroveOS; acasia is great.", options) == "uh kay sha ships grove O S; uh kay sha is great.")
        #expect(say("Acasias and xAcasia stay.", options) == "Acasias and xAcasia stay.")
    }

    @Test func applyInsideCodeAndWithTechnicalTermsOff() {
        let entries = [Pronunciation(written: "Kubernetes", spoken: "koo ber net eez")]
        #expect(say("Run `Kubernetes up`.", CleanupOptions(pronunciations: entries)) == "Run koo ber net eez up.")
        #expect(say("Kubernetes runs.", CleanupOptions(speaksTechnicalTerms: false, pronunciations: entries)) == "koo ber net eez runs.")
    }

    @Test func overrideTheBuiltInDictionary() {
        let options = CleanupOptions(pronunciations: [Pronunciation(written: "JSON", spoken: "jay son")])
        #expect(say("Send JSON.", options) == "Send jay son.")
    }

    @Test func blankEntriesAreIgnored() {
        let options = CleanupOptions(pronunciations: [Pronunciation(written: " ", spoken: "x"), Pronunciation(written: "a", spoken: "")])
        #expect(say("A plain sentence.", options) == "A plain sentence.")
    }

    @Test func codableRoundTrip() throws {
        let entries = [Pronunciation(written: "Readout", spoken: "reed out")]
        let data = try JSONEncoder().encode(entries)
        #expect(try JSONDecoder().decode([Pronunciation].self, from: data) == entries)
    }
}

@Suite("Technical speech performance")
struct TechnicalPerformanceTests {
    @Test func largeTechnicalDocumentIsFast() {
        let paragraph = """
        Call `getUserName()` and check `user_id != nil`, then run `git push --force` from src/app/main.ts. \
        OpenTelemetry ships JSON over HTTPS to ClickHouse (see issue #4512, v1.2.3), e.g. via kubectl on k8s.

        ```swift
        let user = try await api.fetchUser(id: userID)
        ```
        """
        var document = ""
        while document.split(whereSeparator: \.isWhitespace).count < 5_000 {
            document += paragraph + "\n\n"
        }
        let start = Date()
        let sentences = SentenceSplitter.split(TextCleaner.clean(document, options: CleanupOptions(codeBlocks: .read)))
        let elapsed = Date().timeIntervalSince(start)
        #expect(sentences.count > 100)
        #expect(elapsed < 1.0, "5,000 technical words took \(elapsed) s")
    }
}
