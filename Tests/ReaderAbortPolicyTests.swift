import Foundation
import Testing
@testable import Glosso

@Suite struct ReaderAbortPolicyTests {
    @Test func aRefusedPassageDoesNotCountTowardTheAbort() {
        // The engine is fine — only this passage was refused. Counting it would let
        // two adjacent refusals stop an article whose remaining blocks translate.
        #expect(ReaderController.countsTowardAbort(TranslationError.contentBlocked("RECITATION")) == false)
        #expect(ReaderController.countsTowardAbort(TranslationError.contentBlocked("SAFETY")) == false)
    }

    @Test func engineFailuresStillCountTowardTheAbort() {
        // These say the engine can't serve at all, so grinding through the remaining
        // blocks would just produce the same error hundreds of times.
        #expect(ReaderController.countsTowardAbort(TranslationError.ollamaUnreachable))
        #expect(ReaderController.countsTowardAbort(TranslationError.cloudUnreachable))
        #expect(ReaderController.countsTowardAbort(TranslationError.quotaExhausted))
        #expect(ReaderController.countsTowardAbort(TranslationError.malformedStream))
        #expect(ReaderController.countsTowardAbort(URLError(.timedOut)))
    }
}
