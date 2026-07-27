import Testing
@testable import Glosso

@Suite struct TokenizerTests {
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

    @Test func keepsApostropheContractionsTogether() {
        #expect(Tokenizer.segments("don't").filter(\.isWord).map(\.text) == ["don't"])
        #expect(Tokenizer.segments("it\u{2019}s").filter(\.isWord).map(\.text) == ["it\u{2019}s"])
    }

    // A hyphen is a separator, so a hyphenated compound is two clickable words.
    @Test func splitsHyphenatedCompounds() {
        #expect(Tokenizer.segments("well-being").filter(\.isWord).map(\.text) == ["well", "being"])
    }
}

@Suite struct FlowComposerTests {
    private func runs(_ input: String) -> [FlowRun] {
        FlowComposer.runs(Tokenizer.segments(input))
    }

    private func rebuilt(_ runs: [FlowRun]) -> String {
        runs.map { run in
            switch run {
            case .chunk(_, let leading, let word, let trailing): leading + word.text + trailing
            case .gap(_, let text, _): text
            }
        }.joined()
    }

    @Test func composingIsLossless() {
        for input in [
            "Witaj świecie, na zawsze.",
            "To (jest) test; naprawdę!",
            "Myślnik — w środku — zdania",
            "well-being",
            "  spacje  na  brzegach  ",
            "",
        ] {
            #expect(rebuilt(runs(input)) == input, "lossless grouping failed for: \(input)")
        }
    }

    @Test func closingPunctuationHugsPreviousWord() {
        let result = runs("świecie, drugie")
        let trailingForŚwiecie = result.compactMap { run -> String? in
            if case .chunk(_, _, let word, let trailing) = run, word.text == "świecie" { return trailing }
            return nil
        }
        #expect(trailingForŚwiecie == [","])
        // No gap may carry the comma — that is exactly the orphan we are preventing.
        #expect(!result.contains { if case .gap(_, let text, _) = $0 { return text.contains(",") } else { return false } })
    }

    @Test func openingPunctuationHugsNextWord() {
        let chunks = runs("to (test) tak").compactMap { run -> (String, String, String)? in
            if case .chunk(_, let leading, let word, let trailing) = run { return (leading, word.text, trailing) }
            return nil
        }
        #expect(chunks.contains { $0 == ("(", "test", ")") })
    }

    @Test func clickableWordExcludesPunctuation() {
        let words = runs("Witaj, świecie!").compactMap { run -> String? in
            if case .chunk(_, _, let word, _) = run { return word.text }
            return nil
        }
        #expect(words == ["Witaj", "świecie"])
    }

    @Test func spacedEmDashStaysInGap() {
        let result = runs("tu — tam")
        #expect(result.contains { if case .gap(_, let text, let ws) = $0 { return text == " — " && !ws } else { return false } })
    }
}
