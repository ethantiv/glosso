import Testing
@testable import Glosso

@Suite struct SecondLanguageTests {
    // The five offered languages, locked so the Settings picker and the persisted
    // raw values can't silently drift.
    @Test func offersExactlyTheFiveConfiguredLanguages() {
        #expect(SecondLanguage.allCases == [.english, .german, .russian, .spanish, .dutch])
    }

    @Test func rawValuesArePersistenceCodes() {
        #expect(SecondLanguage.allCases.map(\.rawValue) == ["en", "de", "ru", "es", "nl"])
    }

    // englishName feeds the prompt instruction; a wrong value would translate to
    // the wrong language.
    @Test func englishNamesDriveThePrompt() {
        #expect(SecondLanguage.english.englishName == "English")
        #expect(SecondLanguage.german.englishName == "German")
        #expect(SecondLanguage.russian.englishName == "Russian")
        #expect(SecondLanguage.spanish.englishName == "Spanish")
        #expect(SecondLanguage.dutch.englishName == "Dutch")
    }

    @Test func displayNamesArePolish() {
        #expect(SecondLanguage.russian.displayName == "rosyjski")
        #expect(SecondLanguage.spanish.displayName == "hiszpański")
        #expect(SecondLanguage.dutch.displayName == "niderlandzki")
    }

    // The popup arrow reads "PL → XX" / "XX → PL" off the second language's code.
    @Test func directionLabelsUseTheLanguageCode() {
        #expect(TranslationDirection.fromPolish(.german).label == "PL → DE")
        #expect(TranslationDirection.toPolish(.german).label == "DE → PL")
        #expect(TranslationDirection.fromPolish(.english).label == "PL → EN")
        #expect(TranslationDirection.unknown.label == "…")
    }
}
