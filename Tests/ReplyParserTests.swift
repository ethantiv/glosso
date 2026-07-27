import Testing
@testable import Glosso

@Suite struct ReplyParserTests {
    @Test func keepsMultiParagraphDraftsIntact() {
        let raw = """
        Dzięki za wiadomość!

        Wpadnę w czwartek o 10.
        ---
        Brzmi dobrze — potwierdzam.
        """
        let drafts = ReplyParser.parse(raw)
        #expect(drafts.count == 2)
        #expect(drafts[0] == "Dzięki za wiadomość!\n\nWpadnę w czwartek o 10.")
        #expect(drafts[1] == "Brzmi dobrze — potwierdzam.")
    }

    @Test func trimsBlocksAndDropsEmptyOnes() {
        let raw = "\n\nPierwsza\n---\n\n\n---\n  Druga  \n"
        let drafts = ReplyParser.parse(raw)
        #expect(drafts == ["Pierwsza", "Druga"])
    }

    @Test func deduplicatesCaseInsensitively() {
        let raw = "Jasne\n---\njasne\n---\nNie, dziękuję"
        let drafts = ReplyParser.parse(raw)
        #expect(drafts == ["Jasne", "Nie, dziękuję"])
    }

    @Test func acceptsLongerAndPaddedSeparators() {
        let raw = "A\n  -----  \nB\n---\nC"
        #expect(ReplyParser.parse(raw) == ["A", "B", "C"])
    }

    @Test func capsTheCount() {
        let raw = (1...10).map(String.init).joined(separator: "\n---\n")
        #expect(ReplyParser.parse(raw).count == ReplyParser.maxCount)
    }

    @Test func emptyInputYieldsNoDrafts() {
        #expect(ReplyParser.parse("   \n\n  ").isEmpty)
    }
}
