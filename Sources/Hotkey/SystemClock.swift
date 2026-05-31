import Foundation

struct SystemClock: TimeSource {
    // Continuous time keeps advancing while the Mac is asleep; systemUptime does
    // not, which would make a Cmd+C before sleep and one after wake look like a
    // sub-0.3s "double" and translate the clipboard on a single press.
    func now() -> TimeInterval {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanos = mach_continuous_time() * UInt64(timebase.numer) / UInt64(timebase.denom)
        return TimeInterval(nanos) / 1_000_000_000
    }
}
