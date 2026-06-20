import Testing
@testable import Glosso

// The rule base (#73) must cover every confusable family we promised to ground, so
// a regression that drops one is caught here rather than silently shipping a gap.
// We assert the RJP section markers because they uniquely identify each family.
@Suite struct PolishSpellingRulesTests {
    @Test func coversEveryPromisedConfusableFamily() {
        let sections = ["(RJP 2.2)", "(RJP 2.3)", "(RJP 3.5)", "(RJP 3.6)",
                        "(RJP 3.7.3)", "(RJP 3.7.2)", "(RJP 3.8)", "(RJP 3.9)",
                        "(RJP 3.12)", "(RJP 4.9)", "(RJP 4.5)", "(RJP 8)"]
        for section in sections {
            #expect(PolishSpellingRules.block.contains(section), "missing \(section)")
        }
    }

    // The ż↔g exemplar (może → mogę) is the canonical confusable; if the rz/ż card
    // ever loses it the grounding stops teaching the one swap learners reach for.
    @Test func rzZetCardKeepsTheGZetExemplar() {
        #expect(PolishSpellingRules.block.contains("może→mogę"))
    }

    // The ó/u card must carry the historical-ó words, so the model can say "góra"
    // is historical instead of fabricating an "ó→o" alternation (#73 hallucination).
    @Test func oUCardListsHistoricalOWords() {
        #expect(PolishSpellingRules.block.contains("HISTORYCZNE"))
        for word in ["góra", "córka", "król", "róża"] {
            #expect(PolishSpellingRules.block.contains(word), "missing historical-ó word \(word)")
        }
    }
}
