import Testing
@testable import Glosso

@Suite struct FormalityTests {
    // The three offered modes, locked so the Settings picker and the persisted
    // raw values can't silently drift.
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

    // The popup's tone pill advances one step per click and wraps around, so the
    // cycle order is what drives the visible/persisted mode.
    @Test func nextCyclesThroughAllModesAndWraps() {
        #expect(Formality.automatic.next == .formal)
        #expect(Formality.formal.next == .informal)
        #expect(Formality.informal.next == .automatic)
    }
}
