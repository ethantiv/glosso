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

    @Test func onlyTheLocalEngineSendsOneBlockPerRequest() {
        // Measured: local per-block wall clock is flat, so batching buys nothing there
        // while multiplying how much work a discarded batch throws away.
        #expect(ReaderController.batchSize(provider: .local, model: "gemma4:26b-mlx") == 1)
        #expect(ReaderController.batchSize(provider: .ollamaCloud, model: OllamaCloudCatalog.defaultModel) > 1)
        #expect(ReaderController.batchSize(provider: .cloud, model: CloudModelCatalog.default.id) > 1)
    }

    @Test func theTwoGeminiModelsDoNotShareABatchSize() {
        // They are bound by opposite things: Flash Lite's cost is nearly fixed per call and its
        // scarce resource is the 500-request day, while Gemma's cost grows with the batch — so one
        // number would either starve Flash Lite's daily budget or stall Gemma's first paint.
        let flashLite = ReaderController.batchSize(provider: .cloud, model: "gemini-3.5-flash-lite")
        let gemma = ReaderController.batchSize(provider: .cloud, model: "gemma-4-31b-it")
        #expect(flashLite > gemma)
    }

    @Test func anUnknownCloudModelFallsBackToTheDefaultsBatch() {
        // The model id comes from settings and the catalog can change under it; a zero or a
        // crash here would silently stop the reader batching at all.
        #expect(ReaderController.batchSize(provider: .cloud, model: "not-a-model") == CloudModelCatalog.default.batch)
        #expect(ReaderController.batchSize(provider: .ollamaCloud, model: "kimi-k3") == OllamaCloudCatalog.batch)
    }

    @Test func everyBatchSizeStaysUnderTheMeasuredCleanCeiling() {
        // Ceilings proven live on the real reader corpus: Gemma clean to 40, Flash Lite to 80
        // (its first failure at 100 was the 8192 output clamp, not the model losing the format).
        #expect(ReaderController.batchSize(provider: .cloud, model: "gemma-4-31b-it") <= 40)
        #expect(ReaderController.batchSize(provider: .cloud, model: "gemini-3.5-flash-lite") <= 80)
        #expect(ReaderController.batchSize(provider: .ollamaCloud, model: "gemma4:31b") <= 40)
    }
}
