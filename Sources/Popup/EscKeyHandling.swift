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
                       explanationVisible: Bool,
                       fixReasonMode: Bool = false) -> EscAction {
        guard keyCode == escKeyCode,
              modifiers.intersection(chordModifiers).isEmpty
        else { return .passThrough }
        // The grammar-diff reason dropdown (issue #51) has no list to peel back to,
        // so Esc closes the whole dropdown in one step rather than the #39 two-step.
        if fixReasonMode { return dropdownVisible ? .closeDropdown : .dismiss }
        // Esc peels back one layer at a time: the "Dlaczego tak?" explanation first
        // (back to the alternatives list, issue #39), then the dropdown, and only a
        // bare Esc with nothing open dismisses the whole panel.
        if explanationVisible { return .closeExplanation }
        return dropdownVisible ? .closeDropdown : .dismiss
    }
}
