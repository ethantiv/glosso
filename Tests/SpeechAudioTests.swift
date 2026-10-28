import Foundation
import NaturalLanguage
import Testing
@testable import Glosso

@Suite struct SpeechAudioTests {
    /// A 16 kHz mono 16-bit WAV; `extraChunk` mimics AVAudioRecorder's `FLLR` padding before `data`.
    static func wav(samples: [Int16], rate: Int = 16_000, extraChunk: Bool = false) -> Data {
        func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8 & 0xff), UInt8(v >> 16 & 0xff), UInt8(v >> 24 & 0xff)] }
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8 & 0xff)] }
        let pcm = samples.flatMap { le16(Int(UInt16(bitPattern: $0))) }
        var body: [UInt8] = Array("WAVE".utf8)
        body += Array("fmt ".utf8) + le32(16) + le16(1) + le16(1) + le32(rate) + le32(rate * 2) + le16(2) + le16(16)
        if extraChunk { body += Array("FLLR".utf8) + le32(3) + [0, 0, 0, 0] }
        body += Array("data".utf8) + le32(pcm.count) + pcm
        return Data(Array("RIFF".utf8) + le32(body.count) + body)
    }

    static func tone(seconds: Double, amplitude: Double = 0.3, rate: Int = 16_000) -> [Int16] {
        (0..<Int(seconds * Double(rate))).map { i in
            Int16(amplitude * 32767 * sin(2 * .pi * 440 * Double(i) / Double(rate)))
        }
    }

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

    @Test func silenceIsNotSpeech() {
        #expect(!SpeechAudio.containsSpeech(wav: Self.wav(samples: Array(repeating: 0, count: 16_000))))
    }

    @Test func shortToneIsNotSpeech() {
        #expect(!SpeechAudio.containsSpeech(wav: Self.wav(samples: Self.tone(seconds: 0.3))))
    }

    @Test func loudEnoughToneIsSpeech() {
        #expect(SpeechAudio.containsSpeech(wav: Self.wav(samples: Self.tone(seconds: 0.6))))
    }

    @Test func extraChunksBeforeDataAreSkipped() {
        #expect(SpeechAudio.containsSpeech(wav: Self.wav(samples: Self.tone(seconds: 0.6), extraChunk: true)))
    }

    @Test func garbageIsNotSpeech() {
        #expect(!SpeechAudio.containsSpeech(wav: Data("not a wav file".utf8)))
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
