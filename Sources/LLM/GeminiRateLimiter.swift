import Foundation

/// UserDefaults is thread-safe but not Sendable — this carries it into the actor without pretending it's a value.
struct DefaultsRef: @unchecked Sendable {
    let defaults: UserDefaults

    init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
}

/// Client-side throttle for the free tier. It blocks rather than fails: ReaderController aborts an article after two consecutive errors.
actor GeminiRateLimiter {
    struct Limits: Sendable, Equatable {
        var rpm: Int
        var tpm: Int
        var rpd: Int
    }

    /// Booked slot. Carries its model so settling can't credit another model's window.
    struct Ticket: Sendable {
        let id: Int
        let model: String
    }

    // Suffixed with the model id: Google's free tier meters each model separately.
    private enum Key {
        static func day(_ model: String) -> String { "gemini.quotaDay.\(model)" }
        static func count(_ model: String) -> String { "gemini.requestsToday.\(model)" }
    }

    private struct Entry {
        var at: Date
        var tokens: Int
        var ticket: Int
    }

    private let limits: @Sendable (String) -> Limits
    private let store: DefaultsRef
    private var defaults: UserDefaults { store.defaults }
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    /// The wait is invisible otherwise: acquire blocks, so the reader's status bar just stops moving.
    private let onWait: @Sendable (TimeInterval) -> Void

    private var windows: [String: [Entry]] = [:]
    private var lastTicket = 0

    init(
        limits: @escaping @Sendable (String) -> Limits = { CloudModelCatalog.limits(for: $0) },
        store: DefaultsRef = DefaultsRef(),
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onWait: @escaping @Sendable (TimeInterval) -> Void = { _ in }
    ) {
        self.onWait = onWait
        self.limits = limits
        self.store = store
        self.now = now
        self.sleep = sleep
    }

    // ponytail: measured 2.39–3.90 bytes per token over 86 live reader prompts (median 2.88), so /4 under-reserves by
    // ~28% at the median and ~40% at the worst — the opposite of safe. It holds only because Google's own 429 backstops
    // it and the reader never approaches the window. Tighten the divisor if the popup path ever starts tripping 429s.
    /// Rough input-token count.
    static func estimateTokens(_ prompt: String) -> Int {
        max(1, prompt.utf8.count / 4)
    }

    /// Waits for the model's per-minute room, then books a slot and returns its ticket. Throws only on the daily quota — waiting can't fix that one.
    func acquire(estimatedTokens: Int, model: String) async throws -> Ticket {
        let limits = limits(model)
        try admitDaily(model: model, limits: limits)
        while true {
            let instant = now()
            var window = windows[model, default: []]
            window.removeAll { instant.timeIntervalSince($0.at) >= 60 }
            let usedTokens = window.reduce(0) { $0 + $1.tokens }
            let fitsRequests = window.count < limits.rpm
            // A prompt bigger than the whole per-minute budget never fits; let it through on an empty window and leave the verdict to the server.
            let fitsTokens = usedTokens + estimatedTokens <= limits.tpm || window.isEmpty
            if fitsRequests && fitsTokens {
                lastTicket += 1
                window.append(Entry(at: instant, tokens: estimatedTokens, ticket: lastTicket))
                windows[model] = window
                return Ticket(id: lastTicket, model: model)
            }
            windows[model] = window
            let oldest = window.map(\.at).min() ?? instant
            let wait = 60 - instant.timeIntervalSince(oldest)
            onWait(max(wait, 0))
            do {
                try await sleep(.milliseconds(Int(max(wait, 0.05) * 1000)))
            } catch {
                // Cancelled mid-wait: the request never went out, so the day gets its slot back.
                refundDaily(model: model)
                throw error
            }
        }
    }

    /// Replaces the estimate with Gemini's real `promptTokenCount`, so the minute is measured against what was actually spent.
    func settle(ticket: Ticket, actualTokens: Int?) {
        guard let actualTokens,
              let index = windows[ticket.model]?.firstIndex(where: { $0.ticket == ticket.id }) else { return }
        windows[ticket.model]?[index].tokens = actualTokens
    }

    /// Backs the Settings quota line, for the model the user currently has selected.
    func quotaUsage(model: String) -> (used: Int, limit: Int) {
        let used = defaults.string(forKey: Key.day(model)) == currentDay()
            ? defaults.integer(forKey: Key.count(model))
            : 0
        return (used, limits(model).rpd)
    }

    private func admitDaily(model: String, limits: Limits) throws {
        let day = currentDay()
        if defaults.string(forKey: Key.day(model)) != day {
            defaults.set(day, forKey: Key.day(model))
            defaults.set(0, forKey: Key.count(model))
        }
        let used = defaults.integer(forKey: Key.count(model))
        guard used < limits.rpd else { throw TranslationError.quotaExhausted }
        defaults.set(used + 1, forKey: Key.count(model))
    }

    // Guarded on the day: a wait that straddled the Pacific rollover must not spend a slot from the new day.
    private func refundDaily(model: String) {
        guard defaults.string(forKey: Key.day(model)) == currentDay() else { return }
        let used = defaults.integer(forKey: Key.count(model))
        guard used > 0 else { return }
        defaults.set(used - 1, forKey: Key.count(model))
    }

    // Google's daily quotas roll over at midnight Pacific, not in the user's zone.
    private func currentDay() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: now())
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
