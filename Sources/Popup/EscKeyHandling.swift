import AppKit

enum EscAction { case passThrough, closeExplanation, closeDropdown, dismiss }

enum EscKeyHandling {
    static let escKeyCode: UInt16 = 53
    // Cmd/Shift/Ctrl/Option+Esc are distinct system shortcuts (Force Quit, etc.)
    // and must never be swallowed — only bare Esc dismisses the popup.
    static let chordModifiers: NSEvent.ModifierFlags = [.command, .shift, .control, .option]

    static func action(keyCode: UInt16,
                       modifiers: NSEvent.ModifierFlags,
                       dropdownVisible: Bool,
                       explanationVisible: Bool) -> EscAction {
        guard keyCode == escKeyCode,
              modifiers.intersection(chordModifiers).isEmpty
        else { return .passThrough }
        // Esc peels back one layer at a time: the "Dlaczego tak?" explanation first
        // (back to the alternatives list, issue #39), then the dropdown, and only a
        // bare Esc with nothing open dismisses the whole panel.
        if explanationVisible { return .closeExplanation }
        return dropdownVisible ? .closeDropdown : .dismiss
    }
}
