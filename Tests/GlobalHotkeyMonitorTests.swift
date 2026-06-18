import AppKit
import Foundation
import Testing
@testable import Glosso

@MainActor
@Suite struct GlobalHotkeyMonitorTests {
    // The configurable action chords (issue #21) resolve to the right callback.
    // Defaults are Ctrl+Cmd+G (fix) and Ctrl+Cmd+T (translate in place).
    @Test func defaultChordsResolveToTheirActions() {
        let monitor = GlobalHotkeyMonitor()
        let cmdCtrl = NSEvent.ModifierFlags([.command, .control]).rawValue
        #expect(monitor.resolveChord(key: "g", modifiers: cmdCtrl, isRepeat: false) == .fix)
        #expect(monitor.resolveChord(key: "t", modifiers: cmdCtrl, isRepeat: false) == .translate)
        // Case-folded, since charactersIgnoringModifiers can report uppercase.
        #expect(monitor.resolveChord(key: "G", modifiers: cmdCtrl, isRepeat: false) == .fix)
    }

    // Plain Cmd+C (the translate trigger), a partial modifier set, and key repeats
    // must not be mistaken for an action chord.
    @Test func nonMatchingPressesResolveToNil() {
        let monitor = GlobalHotkeyMonitor()
        let cmdOnly = NSEvent.ModifierFlags.command.rawValue
        let cmdCtrl = NSEvent.ModifierFlags([.command, .control]).rawValue
        #expect(monitor.resolveChord(key: "c", modifiers: cmdOnly, isRepeat: false) == nil)
        #expect(monitor.resolveChord(key: "g", modifiers: cmdOnly, isRepeat: false) == nil)
        #expect(monitor.resolveChord(key: "g", modifiers: cmdCtrl, isRepeat: true) == nil)
    }

    // A custom chord supplied via chordProvider is honored live (no restart).
    @Test func customChordProviderIsHonored() {
        let cmdOpt = NSEvent.ModifierFlags([.command, .option]).rawValue
        let monitor = GlobalHotkeyMonitor(
            chordProvider: { (KeyChord(key: "r", modifiers: cmdOpt), .translateInPlaceDefault) }
        )
        #expect(monitor.resolveChord(key: "r", modifiers: cmdOpt, isRepeat: false) == .fix)
        #expect(monitor.resolveChord(key: "f", modifiers: NSEvent.ModifierFlags([.command, .control]).rawValue, isRepeat: false) == nil)
    }

    // The baseline must come from the FIRST Cmd+C, not the press that completes
    // the double. An app that copies synchronously on the second press has
    // already bumped changeCount (here 5 -> 6) before our passive monitor runs;
    // sampling the baseline at double-detection would yield 6 and the poll loop
    // (changeCount > baseline) would never fire on the real copy.
    @Test func baselineComesFromTheFirstPress() {
        let monitor = GlobalHotkeyMonitor()
        #expect(monitor.registerPress(changeCount: 5, at: 0) == nil)
        #expect(monitor.registerPress(changeCount: 6, at: 0.1) == 5)
    }

    // A press outside the double-press window is itself a fresh first press, so
    // the next double must baseline against it — not the long-stale earlier one.
    @Test func pressOutsideWindowRebaselines() {
        let monitor = GlobalHotkeyMonitor()
        #expect(monitor.registerPress(changeCount: 5, at: 0) == nil)
        #expect(monitor.registerPress(changeCount: 9, at: 1.0) == nil)
        #expect(monitor.registerPress(changeCount: 11, at: 1.05) == 9)
    }
}
