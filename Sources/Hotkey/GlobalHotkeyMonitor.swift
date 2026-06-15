import AppKit
import ApplicationServices
import Foundation

@MainActor
final class GlobalHotkeyMonitor: HotkeyMonitor {
    enum HotkeyError: Error {
        case accessibilityNotGranted
    }

    var onDoubleCopy: (@MainActor (Int) -> Void)?

    private var monitor: Any?
    private var detector: any DoubleKeyDetecting
    private let clock = SystemClock()
    private let changeCountProvider: @MainActor () -> Int
    private var pendingBaseline: Int?

    init(
        detector: any DoubleKeyDetecting = DoubleCopyDetector(),
        changeCountProvider: @escaping @MainActor () -> Int = { NSPasteboard.general.changeCount }
    ) {
        self.detector = detector
        self.changeCountProvider = changeCountProvider
    }

    func start() throws {
        stop()
        guard AXIsProcessTrusted() else {
            throw HotkeyError.accessibilityNotGranted
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // The global monitor handler is delivered on the main thread, but its SDK
            // signature is not @MainActor; assume isolation synchronously to keep ordering.
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
        // A nil return means AppKit failed to install the monitor (e.g. AX revoked
        // between the check above and here); don't report listening when it isn't.
        guard monitor != nil else { throw HotkeyError.accessibilityNotGranted }
    }

    private func handle(_ event: NSEvent) {
        // Match the typed character, not the physical key position (keyCode 8),
        // so double Cmd+C also fires on Dvorak/AZERTY/Colemak layouts.
        let isC = event.charactersIgnoringModifiers?.lowercased() == "c"
        let chordModifiers: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
        let mods = event.modifierFlags.intersection(chordModifiers)
        guard isC, mods == .command, !event.isARepeat else { return }
        if let baseline = registerPress(changeCount: changeCountProvider(), at: clock.now()) {
            onDoubleCopy?(baseline)
        }
    }

    // Returns the changeCount baseline to translate against when this press
    // completes a double, or nil for a (possible) first press. The baseline is
    // sampled at the FIRST Cmd+C, not when the double is detected: a foreground
    // app that copies synchronously on the second press has already bumped
    // changeCount by the time our passive monitor runs, so a baseline read then
    // would equal the post-copy value and the poll loop would never see it rise.
    func registerPress(changeCount: Int, at now: TimeInterval) -> Int? {
        if detector.registerCopy(at: now) {
            defer { pendingBaseline = nil }
            return pendingBaseline ?? changeCount
        }
        pendingBaseline = changeCount
        return nil
    }

    func stop() {
        // Clear any in-progress double-press window (and its baseline) so a
        // stop/start cycle (e.g. the AX-revocation auto-restart) can't pair a
        // pre-flap Cmd+C with a single post-restart press.
        detector.reset()
        pendingBaseline = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
