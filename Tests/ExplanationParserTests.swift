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

    // Curly double quotes (U+201C/U+201D) are the default an LLM emits for Polish
    // output despite the prompt asking for none, so they must be stripped too.
    @Test func stripsWrappingCurlyDoubleQuotes() {
        #expect(ExplanationParser.clean("“Forma dokonana.”") == "Forma dokonana.")
    }

    // An inner quote (e.g. quoting the word) must survive — only a matched outer
    // pair is stripped, so the explanation's own punctuation stays intact.
    @Test func keepsInnerQuotes() {
        let input = "Słowo „dom\" oznacza budynek."
        #expect(ExplanationParser.clean(input) == input)
    }

    @Test func leavesBareSentenceUnchanged() {
        #expect(ExplanationParser.clean("Forma dokonana wskazuje zakończoną czynność.") == "Forma dokonana wskazuje zakończoną czynność.")
    }
}
