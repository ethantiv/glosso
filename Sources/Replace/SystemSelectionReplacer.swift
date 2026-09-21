import AppKit
import CoreGraphics

@MainActor
final class SystemSelectionReplacer: SelectionReplacing {
    private let vKeyCode: CGKeyCode = 9  // kVK_ANSI_V
    private let cKeyCode: CGKeyCode = 8  // kVK_ANSI_C

    // ponytail: a timer, not paste detection — pasting doesn't bump changeCount, so there is nothing to observe.
    // 1s tolerates apps that dequeue the synthetic Cmd+V late; raise it if a slow Electron target still pastes stale.
    private let restoreDelay: Duration
    private let pasteboard: NSPasteboard
    private let sleep: @Sendable (Duration) async throws -> Void
    private let sendKey: ((CGKeyCode) -> Void)?

    init(pasteboard: NSPasteboard = .general, restoreDelay: Duration = .seconds(1),
         sendKey: ((CGKeyCode) -> Void)? = nil,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.pasteboard = pasteboard
        self.restoreDelay = restoreDelay
        self.sendKey = sendKey
        self.sleep = sleep
    }

    /// Survives across overlapping calls: the second replace must keep the *user's* clipboard, not translation #1.
    private var savedItems: [NSPasteboardItem]?
    private(set) var restoreTask: Task<Void, Never>?

    func replace(with text: String) {
        let pasteboard = self.pasteboard
        restoreTask?.cancel()
        if savedItems == nil { savedItems = PasteboardSnapshot.capture(pasteboard) }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let writtenChangeCount = pasteboard.changeCount
        synthesize(keyCode: vKeyCode)

        let sleep = self.sleep
        let delay = restoreDelay
        restoreTask = Task { @MainActor [weak self] in
            try? await sleep(delay)
            guard let self, !Task.isCancelled else { return }
            defer { self.savedItems = nil }
            let pasteboard = self.pasteboard
            // Someone else owns the clipboard by now — restoring would clobber what the user just copied.
            guard pasteboard.changeCount == writtenChangeCount else { return }
            if let saved = self.savedItems { PasteboardSnapshot.restore(saved, to: pasteboard) }
        }
    }

    func synthesizeCopy() { synthesize(keyCode: cKeyCode) }

    private func synthesize(keyCode: CGKeyCode) {
        if let sendKey { sendKey(keyCode); return }
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
