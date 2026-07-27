import Testing
@testable import Glosso

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

    @Test func articlesCardKeepsBareSingularExemplar() {
        #expect(EnglishGrammarRules.block.contains("*I saw dog"))
    }

    @Test func tenseCardAnchorsPastSimpleToTimeMarkers() {
        #expect(EnglishGrammarRules.block.contains("yesterday"))
        #expect(EnglishGrammarRules.block.contains("Past Simple"))
    }
}
