import Foundation

/// UserDefaults is documented thread-safe but isn't Sendable, so it cannot cross
/// into an actor on its own. This carries it across without pretending it's a value.
struct DefaultsRef: @unchecked Sendable {
    let defaults: UserDefaults

    init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
}

/// Client-side throttle for the free Gemini tier. It blocks rather than fails:
/// ReaderController aborts a whole article after two consecutive errors, so a
/// burst of 429s would kill the translation on its second block.
actor GeminiRateLimiter {
    struct Limits: Sendable {
        var rpm: Int
        var tpm: Int
        var rpd: Int

        // Google's public rate-limit page lists no Gemma rows at all; these are the
        // free-tier numbers the API console reports for Gemma 4.
        static let free = Limits(rpm: 30, tpm: 16_000, rpd: 14_400)
    }

    private enum Key {
        static let day = "gemini.quotaDay"
        static let count = "gemini.requestsToday"
    }

    private struct Entry {
        var at: Date
        var tokens: Int
        var ticket: Int
    }

    private let limits: Limits
    private let store: DefaultsRef
    private var defaults: UserDefaults { store.defaults }
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    private var window: [Entry] = []
    private var lastTicket = 0

    init(
        limits: Limits = .free,
        store: DefaultsRef = DefaultsRef(),
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.limits = limits
        self.store = store
        self.now = now
        self.sleep = sleep
    }

    /// Rough input-token count. Overshoots for Polish, which is the safe direction.
    static func estimateTokens(_ prompt: String) -> Int {
        max(1, prompt.utf8.count / 4)
    }

    /// Waits until the per-minute budget has room, then books a slot. Throws only
    /// when the daily quota is gone — that one no amount of waiting fixes.
    /// Returns a ticket for `settle`.
    func acquire(estimatedTokens: Int) async throws -> Int {
        try admitDaily()
        while true {
            let instant = now()
            window.removeAll { instant.timeIntervalSince($0.at) >= 60 }
            let usedTokens = window.reduce(0) { $0 + $1.tokens }
            let fitsRequests = window.count < limits.rpm
            // A prompt bigger than the whole per-minute budget can never "fit"; let it
            // through on an empty window and leave the verdict to the server.
            let fitsTokens = usedTokens + estimatedTokens <= limits.tpm || window.isEmpty
            if fitsRequests && fitsTokens {
                lastTicket += 1
                window.append(Entry(at: instant, tokens: estimatedTokens, ticket: lastTicket))
                return lastTicket
            }
            let oldest = window.map(\.at).min() ?? instant
            let wait = 60 - instant.timeIntervalSince(oldest)
            try await sleep(.milliseconds(Int(max(wait, 0.05) * 1000)))
        }
    }

    /// Replaces the estimate with the real `promptTokenCount` Gemini reports, so the
    /// next caller measures the minute against what was actually spent.
    func settle(ticket: Int, actualTokens: Int?) {
        guard let actualTokens, let index = window.firstIndex(where: { $0.ticket == ticket }) else { return }
        window[index].tokens = actualTokens
    }

    /// Backs the Settings quota line.
    func quotaUsage() -> (used: Int, limit: Int) {
        let used = defaults.string(forKey: Key.day) == currentDay() ? defaults.integer(forKey: Key.count) : 0
        return (used, limits.rpd)
    }

    private func admitDaily() throws {
        let day = currentDay()
        if defaults.string(forKey: Key.day) != day {
            defaults.set(day, forKey: Key.day)
            defaults.set(0, forKey: Key.count)
        }
        let used = defaults.integer(forKey: Key.count)
        guard used < limits.rpd else { throw TranslationError.quotaExhausted }
        defaults.set(used + 1, forKey: Key.count)
    }

    // Google's daily quotas roll over at midnight Pacific, not in the user's zone.
    private func currentDay() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: now())
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
