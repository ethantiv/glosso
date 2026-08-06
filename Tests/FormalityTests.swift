import Testing
@testable import Glosso

@Suite struct FormalityTests {
    @Test func offersExactlyThreeModes() {
        #expect(Formality.allCases == [.automatic, .formal, .informal])
    }

    @Test func rawValuesArePersistenceCodes() {
        #expect(Formality.allCases.map(\.rawValue) == ["auto", "formal", "informal"])
    }

    @Test func displayNamesFollowTheUILanguage() {
        L10n.$override.withValue(.polish) {
            #expect(Formality.automatic.displayName == "Automatyczny")
            #expect(Formality.formal.displayName == "Formalny")
            #expect(Formality.informal.displayName == "Nieformalny")
        }
        L10n.$override.withValue(.english) {
            #expect(Formality.automatic.displayName == "Automatic")
        }
    }
}
