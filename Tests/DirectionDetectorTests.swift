import Testing
@testable import Glosso

@Suite struct DirectionDetectorTests {
    @Test func polishTextGoesToSecondLanguage() {
        #expect(DirectionDetector.detect("Dzień dobry, jak się masz dzisiaj rano?", primary: .polish, second: .english) == .fromPrimary(.polish, .english))
    }

    @Test func englishTextGoesToPolish() {
        #expect(DirectionDetector.detect("Good morning, how are you doing today?", primary: .polish, second: .english) == .toPrimary(.polish, .english))
    }

    @Test func emptyTextIsUnknown() {
        #expect(DirectionDetector.detect("", primary: .polish, second: .english) == .unknown)
    }

    // Short snippets are the common case (a copied word or phrase). Unconstrained,
    // NLLanguageRecognizer misreads short Polish as another Slavic language and the
    // arrow then lies about the swap the prompt performs.
    @Test func shortPolishPhraseGoesToSecondLanguage() {
        #expect(DirectionDetector.detect("Witaj świecie", primary: .polish, second: .english) == .fromPrimary(.polish, .english))
    }

    @Test func shortEnglishPhraseGoesToPolish() {
        #expect(DirectionDetector.detect("Hello world", primary: .polish, second: .english) == .toPrimary(.polish, .english))
    }

    // PL/EN homographs get misread with low confidence ("Do" → pl 0.75), and since
    // the detection names the prompt's target, committing to it would translate
    // English into English (an echo). Low confidence must fall back to .unknown so
    // the prompt's conditional swap — reliable for the PL↔EN pair — decides instead.
    @Test func ambiguousHomographFallsBackToUnknown() {
        #expect(DirectionDetector.detect("Do", primary: .polish, second: .english) == .unknown)
        #expect(DirectionDetector.detect("To", primary: .polish, second: .english) == .unknown)
    }

    @Test func confidentShortPhraseStillDetected() {
        #expect(DirectionDetector.detect("To do", primary: .polish, second: .english) == .toPrimary(.polish, .english))
    }

    // Single foreign words score ≥0.98 within their constrained pair, so the 0.8
    // floor must not push short non-English input back to the conditional-swap
    // prompt — the one that echoed NL/RU sources, which is the bug this PR fixes.
    @Test func shortDutchWordStillDetected() {
        #expect(DirectionDetector.detect("gezellig", primary: .polish, second: .dutch) == .toPrimary(.polish, .dutch))
    }

    @Test func shortRussianWordStillDetected() {
        #expect(DirectionDetector.detect("привет", primary: .polish, second: .russian) == .toPrimary(.polish, .russian))
    }

    // With a non-English second language the detector must mirror the prompt for
    // that pair too: primary → .fromPrimary(second), the other side → .toPrimary(second).
    @Test func polishGoesToGermanWhenSecondIsGerman() {
        #expect(DirectionDetector.detect("Dzień dobry, jak się masz dzisiaj rano?", primary: .polish, second: .german) == .fromPrimary(.polish, .german))
    }

    @Test func germanTextGoesToPolishWhenSecondIsGerman() {
        #expect(DirectionDetector.detect("Guten Morgen, wie geht es dir heute?", primary: .polish, second: .german) == .toPrimary(.polish, .german))
    }

    // An English primary flips the axis: English text is the "from" side, Polish
    // becomes a regular second language.
    @Test func englishPrimaryDetectsEnglishAsFromSide() {
        #expect(DirectionDetector.detect("Good morning, how are you doing today?", primary: .english, second: .polish) == .fromPrimary(.english, .polish))
    }

    @Test func englishPrimaryDetectsPolishAsSecond() {
        #expect(DirectionDetector.detect("Dzień dobry, jak się masz dzisiaj rano?", primary: .english, second: .polish) == .toPrimary(.english, .polish))
    }

    // Automatic second (nil): the detector picks the second side from all supported
    // languages — the direction then carries the resolved concrete language.
    @Test func automaticSecondResolvesGermanText() {
        #expect(DirectionDetector.detect("Guten Morgen, wie geht es dir heute morgen?", primary: .polish, second: nil) == .toPrimary(.polish, .german))
    }

    @Test func automaticSecondResolvesRussianText() {
        #expect(DirectionDetector.detect("Доброе утро, как у тебя дела сегодня?", primary: .polish, second: nil) == .toPrimary(.polish, .russian))
    }

    // Text already in the primary language leaves the target ambiguous under
    // Automatic — fall back to the primary's PL/EN counterpart.
    @Test func automaticSecondFallsBackToCounterpartForPrimaryText() {
        #expect(DirectionDetector.detect("Dzień dobry, jak się masz dzisiaj rano?", primary: .polish, second: nil) == .fromPrimary(.polish, .english))
        #expect(DirectionDetector.detect("Good morning, how are you doing today?", primary: .english, second: nil) == .fromPrimary(.english, .polish))
    }
}
