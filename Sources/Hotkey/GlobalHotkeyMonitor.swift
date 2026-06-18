import AppKit
import ApplicationServices
import Foundation

@MainActor
final class GlobalHotkeyMonitor: HotkeyMonitor {
    enum HotkeyError: Error {
        case accessibilityNotGranted
    }

    var onDoubleCopy: (@MainActor (Int) -> Void)?
    var onFixGrammar: (@MainActor () -> Void)?
    var onTranslateInPlace: (@MainActor () -> Void)?

    enum ChordHit: Equatable { case fix, translate }

    private var monitor: Any?
    private var detector: any DoubleKeyDetecting
    private let clock = SystemClock()
    private let changeCountProvider: @MainActor () -> Int
    private let chordProvider: @MainActor () -> (fix: KeyChord, translate: KeyChord)
    private var pendingBaseline: Int?

    init(
        detector: any DoubleKeyDetecting = DoubleCopyDetector(),
        changeCountProvider: @escaping @MainActor () -> Int = { NSPasteboard.general.changeCount },
        chordProvider: @escaping @MainActor () -> (fix: KeyChord, translate: KeyChord)
            = { (.fixGrammarDefault, .translateInPlaceDefault) }
    ) {
        self.detector = detector
        self.changeCountProvider = changeCountProvider
        self.chordProvider = chordProvider
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
        let chordModifiers: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
        let mods = event.modifierFlags.intersection(chordModifiers)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        // ponytail: char match like Cmd+C; if Control mangles it, switch to keyCode
        switch resolveChord(key: key, modifiers: mods.rawValue, isRepeat: event.isARepeat) {
        case .fix: onFixGrammar?(); return
        case .translate: onTranslateInPlace?(); return
        case nil: break
        }
        guard key == "c", mods == .command, !event.isARepeat else { return }
        if let baseline = registerPress(changeCount: changeCountProvider(), at: clock.now()) {
            onDoubleCopy?(baseline)
        }
    }

    // Pure chord resolution, testable without fabricating an NSEvent. The fix chord
    // wins a tie if a user ever points both at the same combo.
    func resolveChord(key: String, modifiers: UInt, isRepeat: Bool) -> ChordHit? {
        guard !isRepeat else { return nil }
        let chords = chordProvider()
        if chords.fix.matches(key: key, modifiers: modifiers) { return .fix }
        if chords.translate.matches(key: key, modifiers: modifiers) { return .translate }
        return nil
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
