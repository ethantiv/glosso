import AppKit
import Testing
@testable import TranslatorMenuBar

@Suite struct EscKeyHandlingTests {
    private let esc = EscKeyHandling.escKeyCode

    @Test func bareEscWithDropdownClosedDismissesPanel() {
        #expect(EscKeyHandling.action(keyCode: esc, modifiers: [], dropdownVisible: false) == .dismiss)
    }

    @Test func bareEscWithDropdownOpenClosesDropdownFirst() {
        #expect(EscKeyHandling.action(keyCode: esc, modifiers: [], dropdownVisible: true) == .closeDropdown)
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
        #expect(EscKeyHandling.action(keyCode: esc, modifiers: modifier, dropdownVisible: false) == .passThrough)
        #expect(EscKeyHandling.action(keyCode: esc, modifiers: modifier, dropdownVisible: true) == .passThrough)
    }

    @Test func nonEscKeyPassesThrough() {
        #expect(EscKeyHandling.action(keyCode: 0, modifiers: [], dropdownVisible: true) == .passThrough)
    }
}
