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

    @Test func markdownRendersTheEmphasisModelsActuallyUse() {
        #expect(ReaderTemplate.markdown("a **b** c") == "a <strong>b</strong> c")
        #expect(ReaderTemplate.markdown("a *b* c") == "a <em>b</em> c")
        #expect(ReaderTemplate.markdown("użyj `git push`") == "użyj <code>git push</code>")
    }

    @Test func markdownRendersTheReportedAnswer() {
        // The literal string from the bug report: game titles italicised despite the prompt asking for plain prose.
        #expect(ReaderTemplate.markdown("takie tytuły jak *Doom*, *Wolfenstein II: The New Colossus* czy *Rocket League*.")
                == "takie tytuły jak <em>Doom</em>, <em>Wolfenstein II: The New Colossus</em> czy <em>Rocket League</em>.")
    }

    @Test func markdownTurnsListMarkersIntoBullets() {
        #expect(ReaderTemplate.markdown("- pierwszy\n* drugi\n  + trzeci") == "• pierwszy\n• drugi\n• trzeci")
    }

    @Test func markdownBoldsHeadingLines() {
        #expect(ReaderTemplate.markdown("## Tytuł\ntekst") == "<strong>Tytuł</strong>\ntekst")
    }

    @Test func markdownEscapesBeforeItAddsAnyTag() {
        // The whole safety argument: nothing the model writes can reach the page as markup.
        #expect(ReaderTemplate.markdown("<script>alert(1)</script>")
                == "&lt;script&gt;alert(1)&lt;/script&gt;")
        #expect(ReaderTemplate.markdown("Tom & Jerry") == "Tom &amp; Jerry")
        #expect(ReaderTemplate.markdown("<b>*x*</b>") == "&lt;b&gt;<em>x</em>&lt;/b&gt;")
    }

    @Test func markdownLeavesWhatIsNotMarkdownAlone() {
        #expect(ReaderTemplate.markdown("2 * 3 = 6") == "2 * 3 = 6")
        // Two unrelated asterisks on one line: a mark must hug its text to count as emphasis.
        #expect(ReaderTemplate.markdown("3 * 4 = 12 * 2") == "3 * 4 = 12 * 2")
        #expect(ReaderTemplate.markdown("a ** b **") == "a ** b **")
        #expect(ReaderTemplate.markdown("plik snake_case_name.txt") == "plik snake_case_name.txt")
        // Emphasis never pairs across a line break — two list-ish lines must not become one italic run.
        #expect(ReaderTemplate.markdown("gwiazdka *tu\ni *tam") == "gwiazdka *tu\ni *tam")
    }

    private func block(_ id: Int, bytes: Int) -> ReaderTemplate.Block {
        ReaderTemplate.Block(id: id, html: String(repeating: "a", count: bytes), translate: true)
    }

    @Test func batchesRespectTheBlockCountCap() {
        let packed = ReaderTemplate.batches((0..<7).map { block($0, bytes: 10) }, maxCount: 5)
        #expect(packed.map(\.count) == [5, 2])
        #expect(packed.flatMap { $0 }.map(\.id) == Array(0..<7))
    }

    @Test func batchesCloseEarlyOnTheByteBudget() {
        // Two 2500-byte blocks exceed the budget together, so the batch closes before the count cap.
        let packed = ReaderTemplate.batches((0..<2).map { block($0, bytes: 2500) }, maxCount: 5)
        #expect(packed.map(\.count) == [1, 1])
    }

    @Test func batchesNeverSplitAnOversizedBlock() {
        // Splitting would cut a block's markup in half; it goes alone and keeps its own numPredict instead.
        let packed = ReaderTemplate.batches([block(0, bytes: 9000), block(1, bytes: 10)], maxCount: 5)
        #expect(packed.map(\.count) == [1, 1])
        #expect(packed[0][0].html.utf8.count == 9000)
    }

    @Test func batchesOfOneAreEveryBlockSeparately() {
        // The local provider's setting — it must reproduce today's per-block behaviour exactly.
        let packed = ReaderTemplate.batches((0..<3).map { block($0, bytes: 10) }, maxCount: 1)
        #expect(packed.map(\.count) == [1, 1, 1])
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
