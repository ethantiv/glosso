import Foundation
import NaturalLanguage
import Testing
@testable import Glosso

@Suite struct SpeechAudioTests {
    @Test func chunksPackWholeSentences() {
        let chunks = SpeechAudio.chunks("Pierwsze zdanie. Drugie zdanie! Trzecie?")
        #expect(chunks == ["Pierwsze zdanie. Drugie zdanie! Trzecie?"])
    }

    @Test func chunksRespectTheLimit() {
        // Capitalized: the sentence tokenizer doesn't split ". s", so lowercase starts would read as one sentence.
        let sentence = "To jest zdanie " + String(repeating: "słowo ", count: 30).trimmingCharacters(in: .whitespaces) + "."
        let chunks = SpeechAudio.chunks(Array(repeating: sentence, count: 5).joined(separator: " "))
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= SpeechAudio.maxChunkLength })
        #expect(chunks.allSatisfy { $0.hasSuffix(".") })
    }

    @Test func overlongSentenceSplitsAtSpaces() {
        let text = Array(repeating: "wyraz", count: 200).joined(separator: " ")
        let chunks = SpeechAudio.chunks(text)
        #expect(chunks.count >= 3)
        #expect(chunks.allSatisfy { $0.count <= SpeechAudio.maxChunkLength && !$0.hasPrefix(" ") })
        #expect(chunks.joined(separator: " ") == text)
    }

    @Test func blankTextHasNoChunks() {
        #expect(SpeechAudio.chunks("").isEmpty)
        #expect(SpeechAudio.chunks("  \n ").isEmpty)
    }

    @Test func urlsAreDropped() {
        let chunks = SpeechAudio.chunks("Zobacz https://example.com/a?b=1 i wróć.")
        #expect(chunks.count == 1)
        #expect(!chunks[0].contains("http"))
    }

    @Test func voiceFollowsTheLanguage() {
        #expect(SpeechAudio.voice(language: .polish, gender: .female) == "female-polish")
        #expect(SpeechAudio.voice(language: .english, gender: .male) == "male-american-english")
    }

    @Test func languageWithoutAVoiceFallsBackToGender() {
        #expect(SpeechAudio.voice(language: .russian, gender: .female) == "female")
        #expect(SpeechAudio.voice(language: nil, gender: .male) == "male")
    }

    @Test func digitsBecomeWordsOutsideEnglish() {
        let spoken = SpeechAudio.spellingOutNumbers("W 1989 roku głosowało 62% uprawnionych, chleb kosztował 1,25 zł.", language: .polish)
        #expect(spoken.rangeOfCharacter(from: .decimalDigits) == nil, "\(spoken)")
        #expect(spoken.contains("tysiąc dziewięćset osiemdziesiąt dziewięć"))
        #expect(spoken.contains("procent"))
        #expect(!spoken.contains("%"))
    }

    @Test func englishAndUnknownTextKeepTheirDigits() {
        #expect(SpeechAudio.spellingOutNumbers("In 1989, 62% voted.", language: .english) == "In 1989, 62% voted.")
        #expect(SpeechAudio.spellingOutNumbers("1989", language: nil) == "1989")
    }

    @Test func speechModelIsRecognizedWithAnyTag() {
        #expect(SpeechAudio.isSpeechModel("lfm3-audio"))
        #expect(SpeechAudio.isSpeechModel("lfm3-audio:latest"))
        #expect(!SpeechAudio.isSpeechModel("lfm3-audiobook:2b"))
        #expect(!SpeechAudio.isSpeechModel("gemma4:26b-mlx"))
    }

    @Test func versionGate() {
        #expect(SpeechAudio.isSupported(version: "0.40.12"))
        #expect(SpeechAudio.isSupported(version: "0.41.0-rc1"))
        #expect(SpeechAudio.isSupported(version: "1.0.0"))
        #expect(!SpeechAudio.isSupported(version: "0.40.11"))
        #expect(!SpeechAudio.isSupported(version: "0.12.6"))
        #expect(!SpeechAudio.isSupported(version: "garbage"))
    }

    @Test func floatSamplesScaleToUnitRange() {
        let pcm = Data([0x00, 0x80, 0xff, 0x7f, 0x00, 0x00])  // Int16.min, Int16.max, 0
        let samples = SpeechAudio.floatSamples(pcm)
        #expect(samples.count == 3)
        #expect(samples[0] == -1)
        #expect(samples[1] > 0.999 && samples[1] < 1)
        #expect(samples[2] == 0)
    }
}
