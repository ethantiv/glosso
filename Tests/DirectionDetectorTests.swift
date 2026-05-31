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
}
