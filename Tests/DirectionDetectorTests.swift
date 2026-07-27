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

    @Test func shortPolishPhraseGoesToSecondLanguage() {
        #expect(DirectionDetector.detect("Witaj świecie", primary: .polish, second: .english) == .fromPrimary(.polish, .english))
    }

    @Test func shortEnglishPhraseGoesToPolish() {
        #expect(DirectionDetector.detect("Hello world", primary: .polish, second: .english) == .toPrimary(.polish, .english))
    }

    @Test func ambiguousHomographFallsBackToUnknown() {
        #expect(DirectionDetector.detect("Do", primary: .polish, second: .english) == .unknown)
        #expect(DirectionDetector.detect("To", primary: .polish, second: .english) == .unknown)
    }

    @Test func confidentShortPhraseStillDetected() {
        #expect(DirectionDetector.detect("To do", primary: .polish, second: .english) == .toPrimary(.polish, .english))
    }

    @Test func shortDutchWordStillDetected() {
        #expect(DirectionDetector.detect("gezellig", primary: .polish, second: .dutch) == .toPrimary(.polish, .dutch))
    }

    @Test func shortRussianWordStillDetected() {
        #expect(DirectionDetector.detect("привет", primary: .polish, second: .russian) == .toPrimary(.polish, .russian))
    }

    @Test func polishGoesToGermanWhenSecondIsGerman() {
        #expect(DirectionDetector.detect("Dzień dobry, jak się masz dzisiaj rano?", primary: .polish, second: .german) == .fromPrimary(.polish, .german))
    }

    @Test func germanTextGoesToPolishWhenSecondIsGerman() {
        #expect(DirectionDetector.detect("Guten Morgen, wie geht es dir heute?", primary: .polish, second: .german) == .toPrimary(.polish, .german))
    }

    @Test func englishPrimaryDetectsEnglishAsFromSide() {
        #expect(DirectionDetector.detect("Good morning, how are you doing today?", primary: .english, second: .polish) == .fromPrimary(.english, .polish))
    }

    @Test func englishPrimaryDetectsPolishAsSecond() {
        #expect(DirectionDetector.detect("Dzień dobry, jak się masz dzisiaj rano?", primary: .english, second: .polish) == .toPrimary(.english, .polish))
    }

    @Test func automaticSecondResolvesGermanText() {
        #expect(DirectionDetector.detect("Guten Morgen, wie geht es dir heute morgen?", primary: .polish, second: nil) == .toPrimary(.polish, .german))
    }

    @Test func automaticSecondResolvesRussianText() {
        #expect(DirectionDetector.detect("Доброе утро, как у тебя дела сегодня?", primary: .polish, second: nil) == .toPrimary(.polish, .russian))
    }

    @Test func automaticSecondFallsBackToCounterpartForPrimaryText() {
        #expect(DirectionDetector.detect("Dzień dobry, jak się masz dzisiaj rano?", primary: .polish, second: nil) == .fromPrimary(.polish, .english))
        #expect(DirectionDetector.detect("Good morning, how are you doing today?", primary: .english, second: nil) == .fromPrimary(.english, .polish))
    }
}
