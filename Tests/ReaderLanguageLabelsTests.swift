import Foundation
import Testing
@testable import Glosso

@Suite struct ReaderLanguageLabelsTests {
    private let dutch = """
    <p>Het programma „Grachten van Morgen” bepaalt dat vanaf 2032 geen commercieel \
    transport op verbrandingsmotoren de historische binnenstad in mag. Elektrische \
    dekschuiten verzorgen nu al een derde van de leveringen.</p>
    """

    @Test func labelsAForeignArticleWithBothCodes() {
        let labels = ReaderController.languageLabels(primary: .polish, content: dutch)
        #expect(labels?.translated == "PL")
        #expect(labels?.original == "NL")
    }

    @Test func labelsFollowThePrimaryLanguage() {
        let labels = ReaderController.languageLabels(primary: .english, content: dutch)
        #expect(labels?.translated == "EN")
        #expect(labels?.original == "NL")
    }

    // PL | PL would label a no-op toggle — an article already in the primary
    // keeps the template's word labels instead.
    @Test func articleAlreadyInPrimaryKeepsWordLabels() {
        let polish = "<p>Kanały Amsterdamu przez dziesięciolecia były traktowane jak zaplecze miasta i parkingi dla barek.</p>"
        #expect(ReaderController.languageLabels(primary: .polish, content: polish) == nil)
    }

    // Short or empty text is below the confidence floor — never guess a code
    // off a headline-sized fragment.
    @Test func shortTextKeepsWordLabels() {
        #expect(ReaderController.languageLabels(primary: .polish, content: "<p>To do</p>") == nil)
    }
}
