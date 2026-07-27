import Foundation
import Testing
@testable import Glosso

@Suite struct ReaderTemplateTests {
    @Test func unwrapLeavesPlainTextAlone() {
        #expect(ReaderTemplate.unwrap("  Cześć <b>świecie</b> \n") == "Cześć <b>świecie</b>")
    }

    @Test func unwrapPeelsBareFences() {
        #expect(ReaderTemplate.unwrap("```\n<p>Cześć</p>\n```") == "<p>Cześć</p>")
    }

    @Test func unwrapPeelsLanguageTaggedFences() {
        #expect(ReaderTemplate.unwrap("```html\n<p>Cześć</p>\n```") == "<p>Cześć</p>")
    }

    @Test func unwrapPeelsAnEchoedBlockWrapper() {
        // Flash Lite answers buildBlockTranslation with the prompt's own wrapper around the text.
        #expect(ReaderTemplate.unwrap("<block> Mamy teraz automatyzację dowodów </block>")
                == "Mamy teraz automatyzację dowodów")
    }

    @Test func unwrapPeelsATextOrArticleWrapper() {
        #expect(ReaderTemplate.unwrap("<text>Streszczenie.</text>") == "Streszczenie.")
        #expect(ReaderTemplate.unwrap("<article>\nOdpowiedź.\n</article>") == "Odpowiedź.")
    }

    @Test func unwrapPeelsAWrapperInsideAFence() {
        #expect(ReaderTemplate.unwrap("```html\n<block>\n<p>Cześć</p>\n</block>\n```") == "<p>Cześć</p>")
    }

    @Test func unwrapPeelsAFenceInsideAWrapper() {
        #expect(ReaderTemplate.unwrap("<block>```\n<p>Cześć</p>\n```</block>") == "<p>Cześć</p>")
    }

    @Test func unwrapLeavesUnmatchedOrInnerTagsAlone() {
        // Peeling any of these would eat real article markup.
        #expect(ReaderTemplate.unwrap("<block>Cześć") == "<block>Cześć")
        #expect(ReaderTemplate.unwrap("<p><block>x</block></p>") == "<p><block>x</block></p>")
        #expect(ReaderTemplate.unwrap("<em>a</em> i <em>b</em>") == "<em>a</em> i <em>b</em>")
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

    @Test func callEncodesArgumentsAsJSONStringLiterals() {
        let call = ReaderTemplate.call("glossoApply", "1", #"a "quoted" </script> line"#)

        #expect(call == #"glossoApply("1", "a \"quoted\" <\/script> line")"#)
    }

    @Test func callDoubleEncodesAJSONArrayArgument() {
        let call = ReaderTemplate.call("glossoSetQuestions", #"["A?","B?"]"#)

        #expect(call == #"glossoSetQuestions("[\"A?\",\"B?\"]")"#)
    }
}
