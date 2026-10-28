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
    var onSpeechStart: (@MainActor () -> Void)?
    var onSpeechEnd: (@MainActor () -> Void)?

    enum ChordHit: Equatable { case fix, translate }
    enum SpeechHit: Equatable { case start, end }

    private var monitor: Any?
    private var detector: any DoubleKeyDetecting
    private let clock = SystemClock()
    private let changeCountProvider: @MainActor () -> Int
    private let chordProvider: @MainActor () -> (fix: KeyChord, translate: KeyChord)
    private let speechChordProvider: @MainActor () -> KeyChord?
    private var pendingBaseline: Int?
    /// The held hold-to-talk key; its key-up ends the take even if the modifiers were let go first.
    private var speechKeyCode: UInt16?

    init(
        detector: any DoubleKeyDetecting = DoubleCopyDetector(),
        changeCountProvider: @escaping @MainActor () -> Int = { NSPasteboard.general.changeCount },
        chordProvider: @escaping @MainActor () -> (fix: KeyChord, translate: KeyChord)
            = { (.fixGrammarDefault, .translateInPlaceDefault) },
        speechChordProvider: @escaping @MainActor () -> KeyChord? = { nil }
    ) {
        self.detector = detector
        self.changeCountProvider = changeCountProvider
        self.chordProvider = chordProvider
        self.speechChordProvider = speechChordProvider
    }

    func start() throws {
        stop()
        guard AXIsProcessTrusted() else {
            throw HotkeyError.accessibilityNotGranted
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event)
            }
        }
        guard monitor != nil else { throw HotkeyError.accessibilityNotGranted }
    }

    private func handle(_ event: NSEvent) {
        let chordModifiers: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
        let mods = event.modifierFlags.intersection(chordModifiers)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isKeyUp = event.type == .keyUp
        switch resolveSpeech(key: key, modifiers: mods.rawValue, keyCode: event.keyCode,
                             isRepeat: event.isARepeat, isKeyUp: isKeyUp) {
        case .start: onSpeechStart?(); return
        case .end: onSpeechEnd?(); return
        case nil: break
        }
        guard !isKeyUp else { return }
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

    func resolveChord(key: String, modifiers: UInt, isRepeat: Bool) -> ChordHit? {
        guard !isRepeat else { return nil }
        let chords = chordProvider()
        if chords.fix.matches(key: key, modifiers: modifiers) { return .fix }
        if chords.translate.matches(key: key, modifiers: modifiers) { return .translate }
        return nil
    }

    func resolveSpeech(key: String, modifiers: UInt, keyCode: UInt16, isRepeat: Bool, isKeyUp: Bool) -> SpeechHit? {
        if isKeyUp {
            guard keyCode == speechKeyCode else { return nil }
            speechKeyCode = nil
            return .end
        }
        guard !isRepeat, let chord = speechChordProvider(),
              chord.matches(key: key, modifiers: modifiers) else { return nil }
        // A fresh press while "held" means the key-up was never delivered (secure input hides key events from global
        // monitors). End the stuck take instead of ignoring every press from now on.
        if speechKeyCode != nil {
            speechKeyCode = nil
            return .end
        }
        speechKeyCode = keyCode
        return .start
    }

    func registerPress(changeCount: Int, at now: TimeInterval) -> Int? {
        if detector.registerCopy(at: now) {
            defer { pendingBaseline = nil }
            return pendingBaseline ?? changeCount
        }
        pendingBaseline = changeCount
        return nil
    }

    func stop() {
        detector.reset()
        pendingBaseline = nil
        speechKeyCode = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
