import Testing
@testable import Glosso

@Suite struct PolishSpellingRulesTests {
    @Test func coversEveryPromisedConfusableFamily() {
        let sections = ["(RJP 1)", "(RJP 2.2)", "(RJP 2.3)", "(RJP 3.5)", "(RJP 3.6)",
                        "(RJP 3.7.3)", "(RJP 3.7.2)", "(RJP 3.8)", "(RJP 3.9)",
                        "(RJP 3.12)", "(RJP 4.9)", "(RJP 4.5)", "(RJP 8)"]
        for section in sections {
            #expect(PolishSpellingRules.block.contains(section), "missing \(section)")
        }
    }

    @Test func rzZetCardKeepsTheGZetExemplar() {
        #expect(PolishSpellingRules.block.contains("może→mogę"))
    }

    @Test func oUCardListsHistoricalOWords() {
        #expect(PolishSpellingRules.block.contains("HISTORYCZNE"))
        for word in ["góra", "córka", "król", "róża"] {
            #expect(PolishSpellingRules.block.contains(word), "missing historical-ó word \(word)")
        }
    }

    @Test func coversEveryPromisedStyleFamily() {
        let markers = ["(styl: pleonazmy)", "(styl: kalki)", "(styl: nominalizacje)",
                       "(styl: strona bierna)", "(styl: szyk)", "(styl: zwięzłość)"]
        for marker in markers {
            #expect(PolishSpellingRules.block.contains(marker), "missing \(marker)")
        }
    }
}
