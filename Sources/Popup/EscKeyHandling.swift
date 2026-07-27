import AppKit

enum EscAction { case passThrough, closeExplanation, closeDropdown, dismiss }

enum EscKeyHandling {
    static let escKeyCode: UInt16 = 53
    static let chordModifiers: NSEvent.ModifierFlags = [.command, .shift, .control, .option]

    static func action(keyCode: UInt16,
                       modifiers: NSEvent.ModifierFlags,
                       dropdownVisible: Bool,
                       explanationVisible: Bool,
                       fixReasonMode: Bool = false) -> EscAction {
        guard keyCode == escKeyCode,
              modifiers.intersection(chordModifiers).isEmpty
        else { return .passThrough }
        if fixReasonMode { return dropdownVisible ? .closeDropdown : .dismiss }
        if explanationVisible { return .closeExplanation }
        return dropdownVisible ? .closeDropdown : .dismiss
    }
}
