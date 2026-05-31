import Foundation
import Testing
@testable import TranslatorMenuBar

@Suite struct DoubleCopyDetectorTests {
    @Test func firstCopyIsNeverDouble() {
        var detector = DoubleCopyDetector()
        #expect(detector.registerCopy(at: 0) == false)
    }

    @Test func secondCopyWithinWindowIsDouble() {
        var detector = DoubleCopyDetector()
        _ = detector.registerCopy(at: 0)
        #expect(detector.registerCopy(at: 0.2) == true)
    }

    @Test func secondCopyTooLateIsNotDouble() {
        var detector = DoubleCopyDetector()
        _ = detector.registerCopy(at: 0)
        #expect(detector.registerCopy(at: 0.5) == false)
    }

    @Test(arguments: [
        (0.05, true),
        (0.30, true),
        (0.31, false),
        (1.0, false),
    ])
    func windowBoundaries(gap: TimeInterval, expected: Bool) {
        var detector = DoubleCopyDetector()
        _ = detector.registerCopy(at: 0)
        #expect(detector.registerCopy(at: gap) == expected)
    }

    @Test func threeRapidCopiesResetAfterPair() {
        var detector = DoubleCopyDetector()
        #expect(detector.registerCopy(at: 0) == false)
        #expect(detector.registerCopy(at: 0.1) == true)
        #expect(detector.registerCopy(at: 0.15) == false)
    }
}
