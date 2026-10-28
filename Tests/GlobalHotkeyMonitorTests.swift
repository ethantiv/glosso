import AppKit
import Foundation
import Testing
@testable import Glosso

@MainActor
@Suite struct GlobalHotkeyMonitorTests {
    @Test func defaultChordsResolveToTheirActions() {
        let monitor = GlobalHotkeyMonitor()
        let cmdCtrl = NSEvent.ModifierFlags([.command, .control]).rawValue
        #expect(monitor.resolveChord(key: "g", modifiers: cmdCtrl, isRepeat: false) == .fix)
        #expect(monitor.resolveChord(key: "t", modifiers: cmdCtrl, isRepeat: false) == .translate)
        // Case-folded, since charactersIgnoringModifiers can report uppercase.
        #expect(monitor.resolveChord(key: "G", modifiers: cmdCtrl, isRepeat: false) == .fix)
    }

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

    @Test func speechChordStartsOnPressAndEndsOnItsKeyUp() {
        let cmdCtrl = NSEvent.ModifierFlags([.command, .control]).rawValue
        let monitor = GlobalHotkeyMonitor(speechChordProvider: { KeyChord(key: "m", modifiers: cmdCtrl) })
        #expect(monitor.resolveSpeech(key: "m", modifiers: cmdCtrl, keyCode: 46, isRepeat: false, isKeyUp: false) == .start)
        #expect(monitor.resolveSpeech(key: "m", modifiers: cmdCtrl, keyCode: 46, isRepeat: true, isKeyUp: false) == nil)
        #expect(monitor.resolveSpeech(key: "x", modifiers: 0, keyCode: 7, isRepeat: false, isKeyUp: true) == nil)
        // The modifiers may already be up when the key itself is released.
        #expect(monitor.resolveSpeech(key: "m", modifiers: 0, keyCode: 46, isRepeat: false, isKeyUp: true) == .end)
        #expect(monitor.resolveSpeech(key: "m", modifiers: 0, keyCode: 46, isRepeat: false, isKeyUp: true) == nil)
    }

    @Test func aLostKeyUpIsRecoveredByTheNextPress() {
        let cmdCtrl = NSEvent.ModifierFlags([.command, .control]).rawValue
        let monitor = GlobalHotkeyMonitor(speechChordProvider: { KeyChord(key: "m", modifiers: cmdCtrl) })
        #expect(monitor.resolveSpeech(key: "m", modifiers: cmdCtrl, keyCode: 46, isRepeat: false, isKeyUp: false) == .start)
        // The key-up went missing; the next press closes the stuck take, the one after starts a new one.
        #expect(monitor.resolveSpeech(key: "m", modifiers: cmdCtrl, keyCode: 46, isRepeat: false, isKeyUp: false) == .end)
        #expect(monitor.resolveSpeech(key: "m", modifiers: cmdCtrl, keyCode: 46, isRepeat: false, isKeyUp: false) == .start)
    }

    @Test func noSpeechChordMeansNoSpeech() {
        let cmdCtrl = NSEvent.ModifierFlags([.command, .control]).rawValue
        let monitor = GlobalHotkeyMonitor()
        #expect(monitor.resolveSpeech(key: "m", modifiers: cmdCtrl, keyCode: 46, isRepeat: false, isKeyUp: false) == nil)
        #expect(monitor.resolveChord(key: "m", modifiers: cmdCtrl, isRepeat: false) == nil)
    }

    @Test func baselineComesFromTheFirstPress() {
        let monitor = GlobalHotkeyMonitor()
        #expect(monitor.registerPress(changeCount: 5, at: 0) == nil)
        #expect(monitor.registerPress(changeCount: 6, at: 0.1) == 5)
    }

    @Test func pressOutsideWindowRebaselines() {
        let monitor = GlobalHotkeyMonitor()
        #expect(monitor.registerPress(changeCount: 5, at: 0) == nil)
        #expect(monitor.registerPress(changeCount: 9, at: 1.0) == nil)
        #expect(monitor.registerPress(changeCount: 11, at: 1.05) == 9)
    }
}
