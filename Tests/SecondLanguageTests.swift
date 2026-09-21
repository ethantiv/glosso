import Testing
@testable import Glosso

@Suite struct SecondLanguageTests {
    @Test func offersExactlyTheConfiguredLanguages() {
        #expect(SecondLanguage.allCases == [.english, .german, .russian, .spanish, .dutch, .french, .polish])
    }

    @Test func rawValuesArePersistenceCodes() {
        #expect(SecondLanguage.allCases.map(\.rawValue) == ["en", "de", "ru", "es", "nl", "fr", "pl"])
    }

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
    @Test(arguments: [
        (TranslationDirection.fromPrimary(.polish, .german), "PL → DE"),
        (.toPrimary(.polish, .german), "DE → PL"),
        (.fromPrimary(.polish, .english), "PL → EN"),
        (.toPrimary(.polish, .english), "EN → PL"),
        (.fromPrimary(.english, .polish), "EN → PL"),
        (.toPrimary(.english, .german), "DE → EN"),
        (.unknown, "…"),
    ])
    func directionLabelsUseTheLanguageCodes(direction: TranslationDirection, label: String) {
        #expect(direction.label == label)
    }

    @Test func primaryCounterpartFlipsThePair() {
        #expect(PrimaryLanguage.polish.counterpart == .english)
        #expect(PrimaryLanguage.english.counterpart == .polish)
        #expect(PrimaryLanguage.polish.asSecond == .polish)
        #expect(PrimaryLanguage.english.asSecond == .english)
    }
}
