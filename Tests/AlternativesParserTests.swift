import Testing
@testable import Glosso

@Suite struct AlternativesParserTests {
    @Test func parsesOnePerLine() {
        let result = AlternativesParser.parse("awesome\ngreat\nincredible", original: "amazing")
        #expect(result == ["awesome", "great", "incredible"])
    }

    @Test func trimsWhitespaceAndDropsBlankLines() {
        let result = AlternativesParser.parse("  awesome  \n\n   \ngreat\n", original: "amazing")
        #expect(result == ["awesome", "great"])
    }

    // The prompt asks for no numbering/bullets, but models add them anyway; strip
    // them defensively so the dropdown shows the bare word.
    @Test func stripsLeadingBulletsAndNumbering() {
        let result = AlternativesParser.parse("1. awesome\n2) great\n- incredible\n• brilliant", original: "amazing")
        #expect(result == ["awesome", "great", "incredible", "brilliant"])
    }

    @Test func stripsWrappingQuotes() {
        let result = AlternativesParser.parse("\"awesome\"\n'great'", original: "amazing")
        #expect(result == ["awesome", "great"])
    }

    @Test func dropsDuplicatesCaseInsensitively() {
        let result = AlternativesParser.parse("great\nGreat\nGREAT\nawesome", original: "amazing")
        #expect(result == ["great", "awesome"])
    }

    // An echo of the clicked word is noise in a list of *alternatives* to it.
    @Test func dropsEchoOfTheOriginalWord() {
        let result = AlternativesParser.parse("amazing\nAmazing\nawesome", original: "amazing")
        #expect(result == ["awesome"])
    }

    @Test func capsAtMaxCount() {
        let raw = (1...20).map { "alt\($0)" }.joined(separator: "\n")
        let result = AlternativesParser.parse(raw, original: "x")
        #expect(result.count == AlternativesParser.maxCount)
    }

    // Polish alternatives keep their diacritics intact through parsing.
    @Test func preservesPolishDiacritics() {
        let result = AlternativesParser.parse("świetnie\nwspaniale\nznakomicie", original: "super")
        #expect(result == ["świetnie", "wspaniale", "znakomicie"])
    }
}
