import AppKit
import Testing
@testable import Glosso

@Suite struct EscKeyHandlingTests {
    private let esc = EscKeyHandling.escKeyCode

    @Test func bareEscWithNothingOpenDismissesPanel() {
        #expect(EscKeyHandling.action(keyCode: esc, modifiers: [], dropdownVisible: false, explanationVisible: false) == .dismiss)
    }

    @Test func bareEscWithDropdownOpenClosesDropdownFirst() {
        #expect(EscKeyHandling.action(keyCode: esc, modifiers: [], dropdownVisible: true, explanationVisible: false) == .closeDropdown)
    }

    @Test func bareEscWithExplanationOpenClosesExplanationFirst() {
        #expect(EscKeyHandling.action(keyCode: esc, modifiers: [], dropdownVisible: true, explanationVisible: true) == .closeExplanation)
    }

    @Test(arguments: [
        NSEvent.ModifierFlags.command,
        .shift,
        .control,
        .option,
    ] as [NSEvent.ModifierFlags])
    func chordEscPassesThrough(_ modifier: NSEvent.ModifierFlags) {
        #expect(EscKeyHandling.action(keyCode: esc, modifiers: modifier, dropdownVisible: false, explanationVisible: false) == .passThrough)
        #expect(EscKeyHandling.action(keyCode: esc, modifiers: modifier, dropdownVisible: true, explanationVisible: true) == .passThrough)
    }

    @Test func fixReasonModeEscClosesDropdownInOneStep() {
        #expect(EscKeyHandling.action(keyCode: esc, modifiers: [], dropdownVisible: true, explanationVisible: true, fixReasonMode: true) == .closeDropdown)
        #expect(EscKeyHandling.action(keyCode: esc, modifiers: [], dropdownVisible: false, explanationVisible: false, fixReasonMode: true) == .dismiss)
    }

    @Test func nonEscKeyPassesThrough() {
        #expect(EscKeyHandling.action(keyCode: 0, modifiers: [], dropdownVisible: true, explanationVisible: true) == .passThrough)
    }
}
