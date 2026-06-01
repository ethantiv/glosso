import Testing
@testable import TranslatorMenuBar

@Suite struct DirectionDetectorTests {
    @Test func polishTextGoesToEnglish() {
        #expect(DirectionDetector.detect("Dzień dobry, jak się masz dzisiaj rano?") == .plToEn)
    }

    @Test func englishTextGoesToPolish() {
        #expect(DirectionDetector.detect("Good morning, how are you doing today?") == .enToPl)
    }

    @Test func emptyTextIsUnknown() {
        #expect(DirectionDetector.detect("") == .unknown)
    }

    // Short snippets are the common case (a copied word or phrase). Unconstrained,
    // NLLanguageRecognizer misreads short Polish as another Slavic language and the
    // arrow then lies about the PL→EN swap the prompt performs.
    @Test func shortPolishPhraseGoesToEnglish() {
        #expect(DirectionDetector.detect("Witaj świecie") == .plToEn)
    }

    @Test func shortEnglishPhraseGoesToPolish() {
        #expect(DirectionDetector.detect("Hello world") == .enToPl)
    }
}
