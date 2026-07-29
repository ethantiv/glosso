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

    @Test func bothCloudsBatchAndOnlyTheLocalEngineDoesNot() {
        // Ollama Cloud meters GPU time, and one request per block re-processes the
        // instruction preamble every time — falling to 1 there spends more, not less.
        #expect(ReaderController.batchSize(for: .cloud) > 1)
        #expect(ReaderController.batchSize(for: .ollamaCloud) == ReaderController.batchSize(for: .cloud))
        #expect(ReaderController.batchSize(for: .local) == 1)
    }
}
