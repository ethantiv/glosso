import Testing
@testable import Glosso

@Suite struct SanityTests {
    @Test func directionLabels() {
        #expect(TranslationDirection.fromPrimary(.polish, .english).label == "PL → EN")
        #expect(TranslationDirection.toPrimary(.polish, .english).label == "EN → PL")
        #expect(TranslationDirection.unknown.label == "…")
    }

    @Test func defaultConfigIsLocalNoThink() {
        #expect(LLMConfig.default.think == false)
        #expect(LLMConfig.default.temperature == 0)
        #expect(LLMConfig.default.model == "gemma4:26b-mlx")
        #expect(LLMConfig.default.keepAlive == "30m")
    }
}
