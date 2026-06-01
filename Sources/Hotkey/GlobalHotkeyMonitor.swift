import AppKit
import ApplicationServices
import Foundation

@MainActor
final class GlobalHotkeyMonitor: HotkeyMonitor {
    enum HotkeyError: Error {
        case accessibilityNotGranted
    }

    var onDoubleCopy: (@MainActor () -> Void)?

    private var monitor: Any?
    private var detector: any DoubleKeyDetecting
    private let clock: any TimeSource

    init(detector: any DoubleKeyDetecting = DoubleCopyDetector(), clock: any TimeSource = SystemClock()) {
        self.detector = detector
        self.clock = clock
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
        if detector.registerCopy(at: clock.now()) {
            onDoubleCopy?()
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
