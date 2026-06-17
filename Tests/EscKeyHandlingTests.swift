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

    // The explanation is the innermost layer: Esc peels it back to the alternatives
    // list before it would close the dropdown (issue #39).
    @Test func bareEscWithExplanationOpenClosesExplanationFirst() {
        #expect(EscKeyHandling.action(keyCode: esc, modifiers: [], dropdownVisible: true, explanationVisible: true) == .closeExplanation)
    }

    // Cmd/Shift/Ctrl/Option+Esc are system shortcuts and must reach the OS/app
    // regardless of popup state.
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

    // The grammar-diff reason dropdown (issue #51) has no alternatives list to peel
    // back to, so a bare Esc closes the whole dropdown in one step — ignoring
    // explanationVisible — and a bare Esc with it already closed dismisses the panel.
    @Test func fixReasonModeEscClosesDropdownInOneStep() {
        #expect(EscKeyHandling.action(keyCode: esc, modifiers: [], dropdownVisible: true, explanationVisible: true, fixReasonMode: true) == .closeDropdown)
        #expect(EscKeyHandling.action(keyCode: esc, modifiers: [], dropdownVisible: false, explanationVisible: false, fixReasonMode: true) == .dismiss)
    }

    @Test func nonEscKeyPassesThrough() {
        #expect(EscKeyHandling.action(keyCode: 0, modifiers: [], dropdownVisible: true, explanationVisible: true) == .passThrough)
    }
}
