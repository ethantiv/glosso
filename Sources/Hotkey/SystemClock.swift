import Foundation

struct SystemClock: TimeSource {
    func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
