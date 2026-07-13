import Testing
@testable import Glosso

@Suite struct DirectionDetectorTests {
    @Test func polishTextGoesToSecondLanguage() {
        #expect(DirectionDetector.detect("Dzień dobry, jak się masz dzisiaj rano?", second: .english) == .fromPolish(.english))
    }

    @Test func englishTextGoesToPolish() {
        #expect(DirectionDetector.detect("Good morning, how are you doing today?", second: .english) == .toPolish(.english))
    }

    @Test func emptyTextIsUnknown() {
        #expect(DirectionDetector.detect("", second: .english) == .unknown)
    }

    // Short snippets are the common case (a copied word or phrase). Unconstrained,
    // NLLanguageRecognizer misreads short Polish as another Slavic language and the
    // arrow then lies about the swap the prompt performs.
    @Test func shortPolishPhraseGoesToSecondLanguage() {
        #expect(DirectionDetector.detect("Witaj świecie", second: .english) == .fromPolish(.english))
    }

    @Test func shortEnglishPhraseGoesToPolish() {
        #expect(DirectionDetector.detect("Hello world", second: .english) == .toPolish(.english))
    }

    // PL/EN homographs get misread with low confidence ("Do" → pl 0.75), and since
    // the detection names the prompt's target, committing to it would translate
    // English into English (an echo). Low confidence must fall back to .unknown so
    // the prompt's conditional swap — reliable for the PL↔EN pair — decides instead.
    @Test func ambiguousHomographFallsBackToUnknown() {
        #expect(DirectionDetector.detect("Do", second: .english) == .unknown)
        #expect(DirectionDetector.detect("To", second: .english) == .unknown)
    }

    @Test func confidentShortPhraseStillDetected() {
        #expect(DirectionDetector.detect("To do", second: .english) == .toPolish(.english))
    }

    // With a non-English second language the detector must mirror the prompt for
    // that pair too: Polish → .fromPolish(second), the other side → .toPolish(second).
    @Test func polishGoesToGermanWhenSecondIsGerman() {
        #expect(DirectionDetector.detect("Dzień dobry, jak się masz dzisiaj rano?", second: .german) == .fromPolish(.german))
    }

    @Test func germanTextGoesToPolishWhenSecondIsGerman() {
        #expect(DirectionDetector.detect("Guten Morgen, wie geht es dir heute?", second: .german) == .toPolish(.german))
    }
}
