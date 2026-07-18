import Foundation
import Testing
@testable import Glosso

@Suite struct ReaderTemplateTests {
    @Test func stripFencesLeavesPlainTextAlone() {
        #expect(ReaderTemplate.stripFences("  Cześć <b>świecie</b> \n") == "Cześć <b>świecie</b>")
    }

    @Test func stripFencesPeelsBareFences() {
        #expect(ReaderTemplate.stripFences("```\n<p>Cześć</p>\n```") == "<p>Cześć</p>")
    }

    @Test func stripFencesPeelsLanguageTaggedFences() {
        #expect(ReaderTemplate.stripFences("```html\n<p>Cześć</p>\n```") == "<p>Cześć</p>")
    }

    @Test func decodesBlockListReturnedByGlossoSetArticle() throws {
        let json = #"[{"id":0,"html":"Hello <em>world</em>","translate":true},{"id":1,"html":"<img src=\"https://x.com/a.png\">","translate":false}]"#
        let blocks = try JSONDecoder().decode([ReaderTemplate.Block].self, from: Data(json.utf8))

        #expect(blocks.count == 2)
        #expect(blocks[0].id == 0)
        #expect(blocks[0].translate)
        #expect(blocks[0].html == "Hello <em>world</em>")
        #expect(!blocks[1].translate)
    }

    // Article text goes into the page exclusively through JSON string literals —
    // raw interpolation would let a quote or </script> break out of the call.
    @Test func callEncodesArgumentsAsJSONStringLiterals() {
        let call = ReaderTemplate.call("glossoApply", "1", #"a "quoted" </script> line"#)

        #expect(call == #"glossoApply("1", "a \"quoted\" <\/script> line")"#)
    }

    // The chat's question list travels as ONE JSON-array string (call takes only
    // String args); JS JSON.parses it back. Pins the double-encoding contract
    // the controller and glossoSetQuestions rely on.
    @Test func callDoubleEncodesAJSONArrayArgument() {
        let call = ReaderTemplate.call("glossoSetQuestions", #"["A?","B?"]"#)

        #expect(call == #"glossoSetQuestions("[\"A?\",\"B?\"]")"#)
    }
}
