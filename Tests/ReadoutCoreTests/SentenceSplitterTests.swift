import Foundation
import Testing
@testable import ReadoutCore

@Suite("Sentence splitter")
struct SentenceSplitterTests {
    @Test func splitsOnSentenceEndings() {
        #expect(SentenceSplitter.split("Hello world. How are you? I am fine!") == [
            "Hello world.", "How are you?", "I am fine!",
        ])
    }

    @Test func keepsDecimalsAndCommonAbbreviations() {
        #expect(SentenceSplitter.split("Pi is about 3.14 today. Dr. Smith agreed.") == [
            "Pi is about 3.14 today.", "Dr. Smith agreed.",
        ])
    }

    @Test func blankLinesSeparateSentences() {
        #expect(SentenceSplitter.split("Heading without a full stop\n\nBody text here") == [
            "Heading without a full stop", "Body text here",
        ])
    }

    @Test func singleNewlinesAreSpaces() {
        #expect(SentenceSplitter.split("This sentence\nwraps across\n  lines. Next one.") == [
            "This sentence wraps across lines.", "Next one.",
        ])
    }

    @Test func listMarkersStayWithTheirItem() {
        #expect(SentenceSplitter.split("1. Open the app.") == ["1. Open the app."])
    }

    @Test func punctuationOnlyFragmentsAreNotSentences() {
        let sentences = SentenceSplitter.split("Wait ... what?\n\n---\n\n!!!")
        #expect(sentences.allSatisfy { $0.containsSpeakableCharacters })
        #expect(sentences.joined(separator: " ").contains("what?"))
    }

    @Test func emptyInput() {
        #expect(SentenceSplitter.split("").isEmpty)
        #expect(SentenceSplitter.split(" \n\n \t ").isEmpty)
    }

    @Test func urduAndArabicFullStops() {
        #expect(SentenceSplitter.split("یہ پہلا جملہ ہے۔ یہ دوسرا جملہ ہے۔").count == 2)
        #expect(SentenceSplitter.split("هل أنت بخير؟ نعم أنا بخير.").count == 2)
    }

    @Test func longSentencesAreChunkedAtNaturalBreaks() {
        let clause = "the quick brown fox jumps over the lazy dog"
        let sentence = Array(repeating: clause, count: 20).joined(separator: ", ") + "."
        let parts = SentenceSplitter.split(sentence, maximumLength: 120)
        #expect(parts.count > 1)
        #expect(parts.allSatisfy { $0.count <= 120 })
        #expect(parts.dropLast().allSatisfy { $0.hasSuffix(",") })
        #expect(words(parts.joined(separator: " ")) == words(sentence))
    }

    @Test func textWithoutSpacesIsHardCut() {
        let blob = String(repeating: "x", count: 500)
        let parts = SentenceSplitter.split(blob, maximumLength: 100)
        #expect(parts.count == 5)
        #expect(parts.joined() == blob)
    }

    @Test func noWordsAreLost() {
        let text = "First sentence here. Second one, with a comma! Third? Fourth: done.\n\nNew paragraph."
        #expect(words(SentenceSplitter.split(text).joined(separator: " ")) == words(text))
    }

    @Test func fiveThousandWordsAreReadyQuickly() {
        let paragraph = """
        Readout speaks the selected text sentence by sentence, so the first words play while the rest waits. \
        It never sends anything over the network & it cleans **Markdown** first, e.g. tables -> sentences. \
        See https://example.com/docs for details.
        """
        var document = ""
        while words(document).count < 5_000 {
            document += paragraph + "\n\n"
        }
        let start = Date()
        let sentences = SentenceSplitter.split(TextCleaner.clean(document))
        let elapsed = Date().timeIntervalSince(start)
        #expect(sentences.count > 100)
        #expect(elapsed < 0.5, "Cleaning and splitting 5,000 words took \(elapsed) s")
    }

    private func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}

@Suite("Language detection")
struct LanguageDetectorTests {
    @Test func detectsClearLanguages() {
        #expect(LanguageDetector.dominantLanguage(of: "This is a perfectly ordinary English sentence about the weather.") == "en")
        #expect(LanguageDetector.dominantLanguage(of: "Ceci est une phrase tout à fait ordinaire en français sur la météo.") == "fr")
    }

    @Test func ignoresShortText() {
        #expect(LanguageDetector.dominantLanguage(of: "OK") == nil)
    }

    @Test func comparesBaseLanguages() {
        #expect(LanguageDetector.isSameLanguage("en-GB", "en_US"))
        #expect(!LanguageDetector.isSameLanguage("en-US", "ur-PK"))
    }
}
