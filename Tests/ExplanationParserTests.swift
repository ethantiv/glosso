import Testing
@testable import Glosso

@Suite struct ExplanationParserTests {
    @Test func trimsSurroundingWhitespaceAndNewlines() {
        #expect(ExplanationParser.clean("  \n Forma dokonana. \n ") == "Forma dokonana.")
    }

    @Test func stripsWrappingStraightQuotes() {
        #expect(ExplanationParser.clean("\"Czasownik na końcu zdania podrzędnego.\"") == "Czasownik na końcu zdania podrzędnego.")
    }

    @Test func stripsWrappingPolishQuotes() {
        #expect(ExplanationParser.clean("„Rzeczownik rodzaju żeńskiego.”") == "Rzeczownik rodzaju żeńskiego.")
    }

    @Test func stripsWrappingCurlyDoubleQuotes() {
        #expect(ExplanationParser.clean("“Forma dokonana.”") == "Forma dokonana.")
    }

    @Test func keepsInnerQuotes() {
        let input = "Słowo „dom\" oznacza budynek."
        #expect(ExplanationParser.clean(input) == input)
    }

    @Test func leavesBareSentenceUnchanged() {
        #expect(ExplanationParser.clean("Forma dokonana wskazuje zakończoną czynność.") == "Forma dokonana wskazuje zakończoną czynność.")
    }
}
