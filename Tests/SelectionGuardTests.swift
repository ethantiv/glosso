import Testing
@testable import TranslatorMenuBar

struct SelectionGuardTests {
    @Test func changeCountNotIncreasedThrowsNothingSelected() {
        #expect(throws: CaptureError.nothingSelected) {
            try SelectionGuard.validate(currentChangeCount: 5, baselineChangeCount: 5, string: "Cześć")
        }
    }

    @Test func nilStringThrowsEmptyOrNonText() {
        #expect(throws: CaptureError.emptyOrNonText) {
            try SelectionGuard.validate(currentChangeCount: 6, baselineChangeCount: 5, string: nil)
        }
    }

    @Test func whitespaceOnlyStringThrowsEmptyOrNonText() {
        #expect(throws: CaptureError.emptyOrNonText) {
            try SelectionGuard.validate(currentChangeCount: 6, baselineChangeCount: 5, string: "   \n\t  ")
        }
    }

    @Test func nonEmptyStringIsReturned() throws {
        let result = try SelectionGuard.validate(currentChangeCount: 6, baselineChangeCount: 5, string: "Cześć")
        #expect(result == "Cześć")
    }

    @Test func surroundingWhitespacePreserved() throws {
        let result = try SelectionGuard.validate(currentChangeCount: 6, baselineChangeCount: 5, string: "  hej  ")
        #expect(result == "  hej  ")
    }

    @Test func nonEmptyTextRejectsNil() {
        #expect(throws: CaptureError.emptyOrNonText) {
            try SelectionGuard.nonEmptyText(nil)
        }
    }

    @Test func nonEmptyTextRejectsWhitespaceOnly() {
        #expect(throws: CaptureError.emptyOrNonText) {
            try SelectionGuard.nonEmptyText("   \n\t  ")
        }
    }

    @Test func nonEmptyTextReturnsText() throws {
        let result = try SelectionGuard.nonEmptyText("Cześć")
        #expect(result == "Cześć")
    }
}
