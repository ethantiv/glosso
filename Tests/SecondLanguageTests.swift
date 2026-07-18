import Testing
@testable import Glosso

@Suite struct SecondLanguageTests {
    // The offered languages, locked so the Settings picker and the persisted
    // raw values can't silently drift. Polish is last: it joined the list when
    // the primary language became configurable (it shows only under an English
    // primary), appended so the existing picker order didn't churn.
    @Test func offersExactlyTheConfiguredLanguages() {
        #expect(SecondLanguage.allCases == [.english, .german, .russian, .spanish, .dutch, .french, .polish])
    }

    @Test func rawValuesArePersistenceCodes() {
        #expect(SecondLanguage.allCases.map(\.rawValue) == ["en", "de", "ru", "es", "nl", "fr", "pl"])
    }

    // englishName feeds the prompt instruction; a wrong value would translate to
    // the wrong language.
    @Test func englishNamesDriveThePrompt() {
        #expect(SecondLanguage.english.englishName == "English")
        #expect(SecondLanguage.german.englishName == "German")
        #expect(SecondLanguage.russian.englishName == "Russian")
        #expect(SecondLanguage.spanish.englishName == "Spanish")
        #expect(SecondLanguage.dutch.englishName == "Dutch")
        #expect(SecondLanguage.french.englishName == "French")
        #expect(SecondLanguage.polish.englishName == "Polish")
    }

    @Test func displayNamesFollowTheUILanguage() {
        L10n.$override.withValue(.polish) {
            #expect(SecondLanguage.russian.displayName == "rosyjski")
            #expect(SecondLanguage.spanish.displayName == "hiszpański")
            #expect(SecondLanguage.dutch.displayName == "niderlandzki")
            #expect(SecondLanguage.french.displayName == "francuski")
        }
        L10n.$override.withValue(.english) {
            #expect(SecondLanguage.russian.displayName == "Russian")
            #expect(SecondLanguage.polish.displayName == "Polish")
        }
    }

    // The popup arrow reads the pair off both sides' codes.
    @Test func directionLabelsUseTheLanguageCodes() {
        #expect(TranslationDirection.fromPrimary(.polish, .german).label == "PL → DE")
        #expect(TranslationDirection.toPrimary(.polish, .german).label == "DE → PL")
        #expect(TranslationDirection.fromPrimary(.polish, .english).label == "PL → EN")
        #expect(TranslationDirection.fromPrimary(.english, .polish).label == "EN → PL")
        #expect(TranslationDirection.toPrimary(.english, .german).label == "DE → EN")
        #expect(TranslationDirection.unknown.label == "…")
    }

    @Test func primaryCounterpartFlipsThePair() {
        #expect(PrimaryLanguage.polish.counterpart == .english)
        #expect(PrimaryLanguage.english.counterpart == .polish)
        #expect(PrimaryLanguage.polish.asSecond == .polish)
        #expect(PrimaryLanguage.english.asSecond == .english)
    }
}
