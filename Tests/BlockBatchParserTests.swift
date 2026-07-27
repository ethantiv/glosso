import Foundation
import Testing
@testable import Glosso

@Suite struct BlockBatchParserTests {
    @Test func parsesOneSegmentPerBlockKeyedByID() {
        let answer = """
        <seg id="12">Cześć <em>świecie</em></seg>
        <seg id="13">Drugi akapit.</seg>
        """
        #expect(BlockBatchParser.parse(answer, ids: [12, 13])
                == [12: "Cześć <em>świecie</em>", 13: "Drugi akapit."])
    }

    @Test func toleratesWhitespaceNewlinesAndSingleQuotedIDs() {
        let answer = "<seg id = '4' >\n  Tekst\n</seg>\n\n<SEG ID=5>Inny</SEG>"
        #expect(BlockBatchParser.parse(answer, ids: [4, 5]) == [4: "Tekst", 5: "Inny"])
    }

    @Test func ignoresProseFencesAndAnEchoedWrapperAroundTheSegments() {
        // Scanning rather than anchoring is what makes the model's packaging habits free to ignore.
        let answer = """
        Oto tłumaczenie:
        ```html
        <block><seg id="1">Pierwszy</seg><seg id="2">Drugi</seg></block>
        ```
        """
        #expect(BlockBatchParser.parse(answer, ids: [1, 2]) == [1: "Pierwszy", 2: "Drugi"])
    }

    @Test func rejectsAMissingSegment() {
        // The corruption case: two blocks merged into one answer would otherwise leave a block silently untranslated.
        #expect(BlockBatchParser.parse("<seg id=\"1\">Pierwszy i drugi</seg>", ids: [1, 2]) == nil)
    }

    @Test func rejectsAnExtraSegment() {
        let answer = "<seg id=\"1\">A</seg><seg id=\"2\">B</seg><seg id=\"3\">C</seg>"
        #expect(BlockBatchParser.parse(answer, ids: [1, 2]) == nil)
    }

    @Test func rejectsReorderedSegments() {
        // Reordering is the visible symptom of the model losing track of which text belongs to which id.
        #expect(BlockBatchParser.parse("<seg id=\"2\">B</seg><seg id=\"1\">A</seg>", ids: [1, 2]) == nil)
    }

    @Test func rejectsAnEmptySegment() {
        #expect(BlockBatchParser.parse("<seg id=\"1\">A</seg><seg id=\"2\">   </seg>", ids: [1, 2]) == nil)
    }
}
