import AppKit
import SwiftUI

extension KeyChord {
    /// Conventional macOS modifier-symbol order (⌃⌥⇧⌘) followed by the key.
    var displayString: String {
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols + key.uppercased()
    }
}

struct KeyChordRecorder: NSViewRepresentable {
    @Binding var chord: KeyChord
    let otherChord: KeyChord

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.chord = chord
        view.otherChord = otherChord
        view.onChange = { chord = $0 }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.chord = chord
        view.otherChord = otherChord
        view.onChange = { chord = $0 }
    }

    final class RecorderView: NSView {
        var chord: KeyChord = .fixGrammarDefault { didSet { needsDisplay = true } }
        var otherChord: KeyChord = .translateInPlaceDefault
        var onChange: ((KeyChord) -> Void)?
        private var isRecording = false { didSet { needsDisplay = true } }

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 96, height: 24) }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            isRecording = true
        }
        override func resignFirstResponder() -> Bool { isRecording = false; return true }

        override func keyDown(with event: NSEvent) {
            guard isRecording else { super.keyDown(with: event); return }
            if event.keyCode == 53 { window?.makeFirstResponder(nil); return } // Esc cancels
            let chordMods: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
            let flags = event.modifierFlags.intersection(chordMods)
            guard flags.contains(.command), flags.contains(.control) || flags.contains(.option),
                  let key = event.charactersIgnoringModifiers?.lowercased(),
                  key.count == 1, let c = key.first, c.isLetter || c.isNumber else {
                NSSound.beep(); return
            }
            let candidate = KeyChord(key: key, modifiers: flags.rawValue)
            // ponytail: only guards against the sibling field; no global/system
            // collision detection — add a CGSSymbolicHotKey probe if it bites.
            guard candidate != otherChord else { NSSound.beep(); return }
            onChange?(candidate)
            window?.makeFirstResponder(nil)
        }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
            (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                         : NSColor.controlBackgroundColor).setFill()
            path.fill()
            (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.lineWidth = isRecording ? 1.5 : 0.5
            path.stroke()

            let text = isRecording ? loc("Naciśnij…", "Press…") : chord.displayString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor,
            ]
            let size = (text as NSString).size(withAttributes: attrs)
            let origin = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
            (text as NSString).draw(at: origin, withAttributes: attrs)
        }
    }
}
