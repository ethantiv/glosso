import Testing
@testable import Glosso

@Suite struct SanityTests {
    @Test func defaultConfigIsLocalNoThink() {
        #expect(LLMConfig.default.think == false)
        #expect(LLMConfig.default.temperature == 0)
        #expect(LLMConfig.default.model == "gemma4:26b-mlx")
        #expect(LLMConfig.default.keepAlive == "60m")
    }

    @Test func speechModelAndEngineFloorArePinned() {
        #expect(SpeechAudio.speechModel == "lfm3-audio")
        #expect(SpeechAudio.minimumEngineVersion == [0, 40, 12])
        #expect(SpeechAudio.sampleRate == 24_000)
    }
}
