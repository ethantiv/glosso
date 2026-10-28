import Foundation
import NaturalLanguage

enum SpeechVoice: String, CaseIterable, Sendable {
    case female
    case male

    var displayName: String {
        switch self {
        case .female: loc("Żeński", "Female")
        case .male: loc("Męski", "Male")
        }
    }
}

/// Pure helpers around the speech model: text chunking, voice names, WAV checks and PCM conversion.
enum SpeechAudio {
    static let speechModel = "lfm3-audio"
    /// `/v1/audio/speech` with `response_format: pcm` streams 16-bit LE mono at this rate.
    static let sampleRate = 24_000
    /// The oldest engine every speech endpoint was verified on; `/v1/audio/speech` alone dates from 0.40.8.
    static let minimumEngineVersion = [0, 40, 12]
    /// Ollama lists the model as `lfm3-audio:<tag>`. It can't translate text, so the translation-model pickers hide it.
    static func isSpeechModel(_ name: String) -> Bool {
        name == speechModel || name.hasPrefix(speechModel + ":")
    }

    /// Short enough that the first chunk starts playing quickly and the next one generates while it plays.
    static let maxChunkLength = 400
    static let minimumSpeechSeconds = 0.5
    /// RMS of the loudest 50 ms window; room noise sits well below it, speech well above. The model transcribes
    /// pure silence as "Okay.", so a silent take must never reach it.
    static let silenceRMS: Float = 0.01

    /// The model's voices are `<gender>-<language>`; NaturalLanguage names map onto its language list.
    private static let voiceLanguages: [NLLanguage: String] = [
        .polish: "polish", .english: "american-english", .german: "german", .french: "french",
        .spanish: "spanish", .dutch: "dutch", .italian: "italian", .portuguese: "portuguese",
        .swedish: "swedish", .danish: "danish", .finnish: "finnish", .greek: "greek",
        .turkish: "turkish", .arabic: "arabic", .hebrew: "hebrew", .japanese: "japanese",
        .korean: "korean", .simplifiedChinese: "chinese",
    ]

    /// A language the model has no voice for (Russian) falls back to the bare gender, which the server accepts.
    static func voice(language: NLLanguage?, gender: SpeechVoice) -> String {
        guard let language, let name = voiceLanguages[language] else { return gender.rawValue }
        return "\(gender.rawValue)-\(name)"
    }

    /// The model reads digits with an English accent in every other language ("1989" came back as "W następstwie
    /// tego roku"), so numbers reach it as words. `%` gets its word only in Polish, the language this was measured on.
    /// shortcut: cardinal nominative only ("w tysiąc dziewięćset osiemdziesiąt dziewięć roku", "1,25 zł" without
    /// "złotych"), no declension — switch Polish to a native synthesizer if that grates.
    static func spellingOutNumbers(_ text: String, language: NLLanguage?) -> String {
        guard let language, language != .english else { return text }
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: language.rawValue)
        let withPercent = language == .polish ? text.replacingOccurrences(of: "%", with: " procent") : text
        return withPercent.replacing(/\d+(?:[.,]\d+)?/) { match in
            let value = Double(match.output.replacingOccurrences(of: ",", with: "."))
            return value.flatMap { formatter.string(from: NSNumber(value: $0)) } ?? String(match.output)
        }
    }

    /// Whole sentences packed up to `maxChunkLength`; an overlong sentence splits at spaces. URLs are dropped, since
    /// read aloud they are noise.
    static func chunks(_ text: String) -> [String] {
        let cleaned = text.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        var sentences: [String] = []
        cleaned.enumerateSubstrings(in: cleaned.startIndex..., options: .bySentences) { sentence, _, _, _ in
            let trimmed = sentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { sentences.append(trimmed) }
        }
        return pack(sentences.flatMap(splitLong), separator: " ")
    }

    private static func splitLong(_ sentence: String) -> [String] {
        guard sentence.count > maxChunkLength else { return [sentence] }
        var words: [String] = []
        for word in sentence.split(separator: " ") {
            var word = String(word)
            // A single unbroken token longer than a chunk is cut hard.
            while word.count > maxChunkLength {
                words.append(String(word.prefix(maxChunkLength)))
                word = String(word.dropFirst(maxChunkLength))
            }
            if !word.isEmpty { words.append(word) }
        }
        return pack(words, separator: " ")
    }

    private static func pack(_ parts: [String], separator: String) -> [String] {
        var packed: [String] = []
        var current = ""
        for part in parts {
            if !current.isEmpty, current.count + separator.count + part.count > maxChunkLength {
                packed.append(current)
                current = ""
            }
            current += current.isEmpty ? part : separator + part
        }
        if !current.isEmpty { packed.append(current) }
        return packed
    }

    /// Numeric dot-by-dot comparison; a pre-release suffix (`-rc1`) is ignored.
    static func isSupported(version: String) -> Bool {
        let core = version.split(separator: "-").first ?? ""
        let numbers = core.split(separator: ".").compactMap { Int($0) }
        guard !numbers.isEmpty else { return false }
        return !numbers.lexicographicallyPrecedes(minimumEngineVersion)
    }

    /// At least `minimumSpeechSeconds` long and with one 50 ms window at or above `silenceRMS`.
    static func containsSpeech(wav: Data) -> Bool {
        guard let decoded = pcm16Samples(wav: wav),
              Double(decoded.samples.count) / Double(decoded.perSecond) >= minimumSpeechSeconds else { return false }
        let samples = decoded.samples, perSecond = decoded.perSecond
        let window = max(perSecond / 20, 1)
        var start = 0
        while start < samples.count {
            let slice = samples[start..<min(start + window, samples.count)]
            let meanSquare = slice.reduce(Float(0)) { $0 + $1 * $1 } / Float(slice.count)
            if meanSquare.squareRoot() >= silenceRMS { return true }
            start += window
        }
        return false
    }

    /// 16-bit LE samples scaled to −1…1.
    static func floatSamples(_ pcm: Data) -> [Float] {
        pcm.withUnsafeBytes { raw in
            (0..<(raw.count / 2)).map { index in
                Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))) / 32768
            }
        }
    }

    /// Walks the RIFF chunks rather than assuming a 44-byte header: AVAudioRecorder writes extra chunks (`FLLR`)
    /// before `data`. `perSecond` is rate × channels, so the duration holds for stereo too.
    private static func pcm16Samples(wav: Data) -> (samples: [Float], perSecond: Int)? {
        let bytes = [UInt8](wav)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        guard bytes.count >= 12,
              bytes[0..<4].elementsEqual("RIFF".utf8),
              bytes[8..<12].elementsEqual("WAVE".utf8) else { return nil }
        var offset = 12
        var perSecond: Int?
        while offset + 8 <= bytes.count {
            let id = bytes[offset..<offset + 4]
            let size = u32(offset + 4)
            let body = offset + 8
            if id.elementsEqual("fmt ".utf8), body + 16 <= bytes.count {
                guard u16(body + 14) == 16 else { return nil }
                perSecond = u32(body + 4) * u16(body + 2)
            } else if id.elementsEqual("data".utf8), let perSecond, perSecond > 0 {
                return (floatSamples(Data(bytes[body..<min(body + size, bytes.count)])), perSecond)
            }
            offset = body + size + (size & 1)
        }
        return nil
    }
}
