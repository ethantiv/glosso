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

    @Test func articleAlreadyInPrimaryKeepsWordLabels() {
        let polish = "<p>Kanały Amsterdamu przez dziesięciolecia były traktowane jak zaplecze miasta i parkingi dla barek.</p>"
        #expect(ReaderController.languageLabels(primary: .polish, content: polish) == nil)
    }

    @Test func shortTextKeepsWordLabels() {
        #expect(ReaderController.languageLabels(primary: .polish, content: "<p>To do</p>") == nil)
    }
}
