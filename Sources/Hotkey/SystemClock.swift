import Foundation

struct SystemClock {
    func now() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }
}
