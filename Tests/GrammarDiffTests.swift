import Testing
@testable import Glosso

@Suite struct GrammarDiffTests {
    private func rebuiltOriginal(_ parts: [DiffPart]) -> String {
        parts.map { part in
            switch part {
            case .same(_, let text): text
            case .change(_, let removed, _): removed
            }
        }.joined()
    }

    private func rebuiltCorrected(_ parts: [DiffPart]) -> String {
        parts.map { part in
            switch part {
            case .same(_, let text): text
            case .change(_, _, let added): added
            }
        }.joined()
    }

    private func changes(_ parts: [DiffPart]) -> [(removed: String, added: String)] {
        parts.compactMap { part in
            if case .change(_, let removed, let added) = part { (removed, added) } else { nil }
        }
    }

    @Test func reconstructsBothSidesLosslessly() {
        let pairs = [
            ("i has went to school", "I have gone to school"),
            ("the cat", "a dog"),
            ("I go school", "I go to school"),
            ("I really really go", "I go"),
            ("Mam dwa kotów", "Mam dwa koty"),
            ("same text", "same text"),
            ("", "fixed text"),
            ("leftover text", ""),
        ]
        for (original, corrected) in pairs {
            let parts = GrammarDiff.parts(original: original, corrected: corrected)
            #expect(rebuiltOriginal(parts) == original, "original round-trip failed for: \(original)")
            #expect(rebuiltCorrected(parts) == corrected, "corrected round-trip failed for: \(corrected)")
        }
    }

    @Test func substitutionMakesEachWordItsOwnChange() {
        let parts = GrammarDiff.parts(original: "i has went", corrected: "I have gone")
        let c = changes(parts)
        #expect(c.count == 3)
        #expect(c.contains { $0 == ("i", "I") })
        #expect(c.contains { $0 == ("has", "have") })
        #expect(c.contains { $0 == ("went", "gone") })
    }

    // A missing word is a change with nothing struck through — only the added text.
    @Test func pureInsertionHasEmptyRemoved() {
        let parts = GrammarDiff.parts(original: "I go school", corrected: "I go to school")
        let c = changes(parts)
        #expect(c.count == 1)
        #expect(c[0].removed == "")
        #expect(c[0].added.contains("to"))
    }

    // An extra word is a change with only struck-through text, nothing added.
    @Test func pureDeletionHasEmptyAdded() {
        let parts = GrammarDiff.parts(original: "I really go", corrected: "I go")
        let c = changes(parts)
        #expect(c.count == 1)
        #expect(c[0].removed.contains("really"))
        #expect(c[0].added == "")
    }

    @Test func identicalTextHasNoChanges() {
        let parts = GrammarDiff.parts(original: "Mam dwa koty", corrected: "Mam dwa koty")
        #expect(changes(parts).isEmpty)
        #expect(parts.count == 1)
    }

    @Test func preservesPolishDiacriticsInChanges() {
        let parts = GrammarDiff.parts(original: "Mam dwa kotów", corrected: "Mam dwa koty")
        let c = changes(parts)
        #expect(c.count == 1)
        #expect(c[0].removed == "kotów")
        #expect(c[0].added == "koty")
    }

    @Test func partsHaveUniqueSequentialIDs() {
        let parts = GrammarDiff.parts(original: "i has went", corrected: "I have gone")
        #expect(parts.map(\.id) == Array(0..<parts.count))
    }
}
