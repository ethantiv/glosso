import AppKit
import CoreGraphics

/// Pastes a translation over the live selection in the frontmost app (issue #22).
/// The popup is a non-activating panel, so the source app keeps focus and its
/// selection — a synthesized Cmd+V lands there. The clipboard is overwritten with
/// the translation and restored afterwards, under the Accessibility consent the app
/// already holds. Cmd+V is universal (native, web and Electron fields alike), unlike
/// setting AXSelectedText, which silently no-ops on web/Electron content.
@MainActor
final class SystemSelectionReplacer: SelectionReplacing {
    private let vKeyCode: CGKeyCode = 9  // kVK_ANSI_V

    // The paste is consumed asynchronously by the target app on its next run loop;
    // restoring the clipboard before that lands would paste the old contents over the
    // selection (looking like no change). Wait well past that window — there is no
    // completion signal for a foreign app's paste, so this errs long; the only cost is
    // the translation lingering on the clipboard briefly.
    private let restoreDelay: Duration = .milliseconds(400)

    func replace(with text: String) {
        let pasteboard = NSPasteboard.general
        // The clipboard holds the copied source text (from the double Cmd+C); only the
        // string is preserved, mirroring the Copy button.
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        synthesizeCommandV()

        guard let saved else { return }
        Task { @MainActor in
            try? await Task.sleep(for: restoreDelay)
            let pasteboard = NSPasteboard.general
            // Only restore if our translation is still on the clipboard. A double
            // Cmd+C started within the restore window already replaced it with a new
            // source — restoring would clobber that capture's clipboard with stale text.
            guard pasteboard.string(forType: .string) == text else { return }
            pasteboard.clearContents()
            pasteboard.setString(saved, forType: .string)
        }
    }

    private func synthesizeCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Suppress the user's physical keyboard during the synthetic burst so a stray
        // real keypress can't merge with it; mouse/system events stay live.
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return }
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        // The annotated session tap is closest to the app, so it bypasses our own Esc
        // CGEventTap (on the session tap), which would otherwise sit in the path and
        // stop the synthetic Cmd+V from reaching the source app.
        vDown.post(tap: .cgAnnotatedSessionEventTap)
        vUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
