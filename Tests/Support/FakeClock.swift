import Foundation
@testable import TranslatorMenuBar

final class FakeClock: TimeSource, @unchecked Sendable {
    var current: TimeInterval

    init(current: TimeInterval = 0) {
        self.current = current
    }

    func now() -> TimeInterval {
        current
    }

    func advance(by delta: TimeInterval) {
        current += delta
    }
}
