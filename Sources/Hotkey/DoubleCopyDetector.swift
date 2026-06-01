import Foundation

struct DoubleCopyDetector: DoubleKeyDetecting {
    let window: TimeInterval
    private var lastCopy: TimeInterval?

    init(window: TimeInterval = 0.3) {
        self.window = window
    }

    mutating func registerCopy(at now: TimeInterval) -> Bool {
        guard let previous = lastCopy else {
            lastCopy = now
            return false
        }
        if now - previous <= window {
            // Reset so a third rapid Cmd+C does not form a second pair with the second press.
            lastCopy = nil
            return true
        }
        lastCopy = now
        return false
    }

    mutating func reset() {
        lastCopy = nil
    }
}
