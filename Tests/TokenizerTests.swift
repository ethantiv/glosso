import Testing
@testable import TranslatorMenuBar

@Suite struct TokenizerTests {
    // The split must be lossless: rebuilding from the segments reproduces the input
    // exactly, so the canonical model.text (used by Copy and reword) never drifts.
    @Test func splitIsLossless() {
        for input in [
            "This is amazing!",
            "  leading and  double   spaces ",
            "Wieloliniowy\ntekst\nz nowymi liniami",
            "Punctuation, semicolons; and — dashes.",
            "",
            "single",
        ] {
            let rebuilt = Tokenizer.segments(input).map(\.text).joined()
            #expect(rebuilt == input, "lossless round-trip failed for: \(input)")
        }
    }

    @Test func classifiesWordsAndSeparators() {
        let segments = Tokenizer.segments("Hi, there")
        #expect(segments.map(\.text) == ["Hi", ", ", "there"])
        #expect(segments.map(\.isWord) == [true, false, true])
    }

    @Test func idsAreSequentialIndices() {
        let segments = Tokenizer.segments("a b c")
        #expect(segments.map(\.id) == Array(0..<segments.count))
    }

    // Polish diacritics are letters, so they stay inside their word as a single token.
    @Test func keepsPolishDiacriticsWithinWords() {
        let segments = Tokenizer.segments("Zażółć gęślą jaźń")
        #expect(segments.filter(\.isWord).map(\.text) == ["Zażółć", "gęślą", "jaźń"])
    }

    // An apostrophe is a word character so English contractions stay one token
    // (clicking "don't" should not split into "don" + "t").
    @Test func keepsApostropheContractionsTogether() {
        #expect(Tokenizer.segments("don't").filter(\.isWord).map(\.text) == ["don't"])
        #expect(Tokenizer.segments("it\u{2019}s").filter(\.isWord).map(\.text) == ["it\u{2019}s"])
    }

    // A hyphen is a separator, so a hyphenated compound is two clickable words.
    @Test func splitsHyphenatedCompounds() {
        #expect(Tokenizer.segments("well-being").filter(\.isWord).map(\.text) == ["well", "being"])
    }
}
