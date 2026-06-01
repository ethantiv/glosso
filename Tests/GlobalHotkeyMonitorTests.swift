import Foundation
import Testing
@testable import TranslatorMenuBar

@MainActor
@Suite struct GlobalHotkeyMonitorTests {
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
