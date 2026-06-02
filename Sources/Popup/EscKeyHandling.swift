import AppKit

enum EscAction { case passThrough, closeDropdown, dismiss }

enum EscKeyHandling {
    static let escKeyCode: UInt16 = 53
    // Cmd/Shift/Ctrl/Option+Esc are distinct system shortcuts (Force Quit, etc.)
    // and must never be swallowed — only bare Esc dismisses the popup.
    static let chordModifiers: NSEvent.ModifierFlags = [.command, .shift, .control, .option]

    static func action(keyCode: UInt16,
                       modifiers: NSEvent.ModifierFlags,
                       dropdownVisible: Bool) -> EscAction {
        guard keyCode == escKeyCode,
              modifiers.intersection(chordModifiers).isEmpty
        else { return .passThrough }
        // Esc closes the alternatives dropdown first if it's open; only a second
        // Esc dismisses the whole panel.
        return dropdownVisible ? .closeDropdown : .dismiss
    }
}
