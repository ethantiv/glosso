import Foundation

struct SystemClock {
    // CLOCK_MONOTONIC_RAW keeps advancing while the Mac is asleep (unlike
    // CLOCK_UPTIME_RAW), so a Cmd+C before sleep and one after wake stay far
    // apart instead of looking like a sub-0.3s "double". Returning nanoseconds
    // directly avoids mach_timebase math (divide-by-zero / overflow).
    func now() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }
}
