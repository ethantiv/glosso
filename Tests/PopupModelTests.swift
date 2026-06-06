import Testing
@testable import Glosso

@MainActor
@Suite struct PopupModelTests {
    @Test func freshModelHasNothingToUndo() {
        let model = PopupModel()
        #expect(model.canUndo == false)
    }

    @Test func snapshotEnablesUndo() {
        let model = PopupModel()
        model.text = "pierwsza wersja"
        model.snapshotForUndo()
        #expect(model.canUndo == true)
    }

    @Test func undoRestoresPreRewordResult() {
        let model = PopupModel()
        model.text = "stara wersja"
        model.truncated = true
        model.phase = .done

        model.snapshotForUndo()

        // The reword replaces the result.
        model.text = "nowa, gorsza wersja"
        model.truncated = false

        model.undo()

        #expect(model.text == "stara wersja")
        #expect(model.truncated == true)
        #expect(model.phase == .done)
        #expect(model.errorMessage == nil)
        // Single level: after one undo there is nothing left to undo.
        #expect(model.canUndo == false)
    }

    @Test func undoClosesAnyOpenDropdown() {
        let model = PopupModel()
        model.text = "wersja"
        model.snapshotForUndo()
        model.openDropdown(for: 3)
        #expect(model.dropdownVisible == true)

        model.undo()

        #expect(model.dropdownVisible == false)
    }

    @Test func undoRecoversFromFailedReword() {
        let model = PopupModel()
        model.text = "dobre tłumaczenie"
        model.phase = .done
        model.snapshotForUndo()

        // The reword failed: the pane reset wiped the text and showError flipped
        // the phase to .error.
        model.text = ""
        model.errorMessage = "Błąd tłumaczenia."
        model.phase = .error

        model.undo()

        #expect(model.text == "dobre tłumaczenie")
        #expect(model.phase == .done)
        #expect(model.errorMessage == nil)
    }

    @Test func clearUndoDropsSnapshot() {
        let model = PopupModel()
        model.text = "wersja"
        model.snapshotForUndo()
        #expect(model.canUndo == true)

        model.clearUndo()

        #expect(model.canUndo == false)
        // undo() is a no-op once the snapshot is cleared.
        model.text = "bieżąca"
        model.undo()
        #expect(model.text == "bieżąca")
    }

    // MARK: Explanation sub-state — "Dlaczego tak?" (issue #39)

    @Test func openExplanationArmsLoadingAndBumpsToken() {
        let model = PopupModel()
        model.openDropdown(for: 2)
        let before = model.explanationRequestToken

        model.openExplanation()

        #expect(model.showingExplanation == true)
        #expect(model.explanationLoading == true)
        #expect(model.explanationText.isEmpty)
        #expect(model.explanationRequestToken == before + 1)
    }

    @Test func closeExplanationReturnsToAlternatives() {
        let model = PopupModel()
        model.openDropdown(for: 2)
        model.openExplanation()
        model.explanationText = "bo gramatyka"
        model.explanationLoading = false

        model.closeExplanation()

        #expect(model.showingExplanation == false)
        #expect(model.explanationText.isEmpty)
        #expect(model.explanationLoading == false)
        // The dropdown itself stays open on the same word.
        #expect(model.dropdownVisible == true)
    }

    @Test func closeDropdownAlsoClearsExplanation() {
        let model = PopupModel()
        model.openDropdown(for: 2)
        model.openExplanation()
        model.explanationText = "bo gramatyka"

        model.closeDropdown()

        #expect(model.dropdownVisible == false)
        #expect(model.showingExplanation == false)
        #expect(model.explanationText.isEmpty)
    }

    @Test func secondSnapshotOverridesFirst() {
        let model = PopupModel()
        model.text = "wersja A"
        model.snapshotForUndo()

        model.text = "wersja B"
        model.snapshotForUndo()

        model.text = "wersja C"
        model.undo()

        // Single-level undo restores the last reword's starting point (B), not A.
        #expect(model.text == "wersja B")
    }
}
