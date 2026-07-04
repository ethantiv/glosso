import Testing
@testable import Glosso

// The English rule base must cover every mistake family we promised to ground for
// Polish speakers writing English (the "(EN: kategoria)" markers uniquely identify
// them), so a regression that drops one is caught here — mirroring
// PolishSpellingRulesTests for the RJP cards.
@Suite struct EnglishGrammarRulesTests {
    @Test func coversEveryPromisedMistakeFamily() {
        let markers = ["(EN: przedimki)", "(EN: przyimki)", "(EN: szyk)", "(EN: czasy)",
                       "(EN: 3. osoba)", "(EN: policzalność)", "(EN: false friends)",
                       "(EN: homofony)", "(EN: interpunkcja)", "(EN: wielkie litery)",
                       "(EN: warunki)", "(EN: gerund/bezokolicznik)"]
        for marker in markers {
            #expect(EnglishGrammarRules.block.contains(marker), "missing \(marker)")
        }
    }

    // The articles card is the highest-value one (Polish has no articles at all);
    // it must keep the canonical bare-singular exemplar the explanations lean on.
    @Test func articlesCardKeepsBareSingularExemplar() {
        #expect(EnglishGrammarRules.block.contains("*I saw dog"))
    }

    // The tense card must anchor Past Simple to explicit past-time markers — the
    // Perfect-vs-Past confusion is the flagship Polish-speaker mistake.
    @Test func tenseCardAnchorsPastSimpleToTimeMarkers() {
        #expect(EnglishGrammarRules.block.contains("yesterday"))
        #expect(EnglishGrammarRules.block.contains("Past Simple"))
    }
}
