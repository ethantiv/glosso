import AppKit
import CoreGraphics

@MainActor
final class SystemSelectionReplacer: SelectionReplacing {
    private let vKeyCode: CGKeyCode = 9  // kVK_ANSI_V
    private let cKeyCode: CGKeyCode = 8  // kVK_ANSI_C

    private let restoreDelay: Duration = .milliseconds(400)

    func replace(with text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        synthesize(keyCode: vKeyCode)

        guard let saved else { return }
        Task { @MainActor in
            try? await Task.sleep(for: restoreDelay)
            let pasteboard = NSPasteboard.general
            guard pasteboard.string(forType: .string) == text else { return }
            pasteboard.clearContents()
            pasteboard.setString(saved, forType: .string)
        }
    }

    func synthesizeCopy() { synthesize(keyCode: cKeyCode) }

    private func synthesize(keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
