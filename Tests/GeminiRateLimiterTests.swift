import Foundation
import Testing
@testable import Glosso

/// A clock the test drives by hand, so waiting on a 60s window costs no wall time.
private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date

    init(_ start: Date) { instant = start }

    var now: Date { lock.withLock { instant } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { instant += seconds }
    }

    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in
            advance(Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
        }
    }
}

@Suite struct GeminiRateLimiterTests {
    private func makeLimiter(
        _ limits: GeminiRateLimiter.Limits,
        clock: FakeClock,
        defaults: UserDefaults? = nil
    ) -> GeminiRateLimiter {
        GeminiRateLimiter(
            limits: limits,
            store: DefaultsRef(defaults ?? UserDefaults(suiteName: UUID().uuidString)!),
            now: { clock.now },
            sleep: clock.sleep
        )
    }

    @Test func requestsBeyondRPMWaitForTheWindowToRoll() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let limiter = makeLimiter(.init(rpm: 2, tpm: 100_000, rpd: 1000), clock: clock)

        _ = try await limiter.acquire(estimatedTokens: 1)
        _ = try await limiter.acquire(estimatedTokens: 1)
        #expect(clock.now.timeIntervalSince1970 == 0)

        // The third has no slot left, so it must sit out the rest of the minute.
        _ = try await limiter.acquire(estimatedTokens: 1)
        #expect(clock.now.timeIntervalSince1970 >= 60)
    }

    @Test func requestsBeyondTPMWaitEvenWhenRequestSlotsRemain() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let limiter = makeLimiter(.init(rpm: 100, tpm: 1000, rpd: 1000), clock: clock)

        _ = try await limiter.acquire(estimatedTokens: 900)
        #expect(clock.now.timeIntervalSince1970 == 0)

        _ = try await limiter.acquire(estimatedTokens: 900)
        #expect(clock.now.timeIntervalSince1970 >= 60)
    }

    @Test func promptLargerThanTheWholeBudgetStillGoesThrough() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let limiter = makeLimiter(.init(rpm: 100, tpm: 1000, rpd: 1000), clock: clock)

        // Nothing would ever make room for it, and blocking forever would kill the reader's chat on long articles.
        _ = try await limiter.acquire(estimatedTokens: 5000)
        #expect(clock.now.timeIntervalSince1970 == 0)
    }

    @Test func settleReplacesTheEstimateWithTheReportedCount() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let limiter = makeLimiter(.init(rpm: 100, tpm: 1000, rpd: 1000), clock: clock)

        let ticket = try await limiter.acquire(estimatedTokens: 900)
        await limiter.settle(ticket: ticket, actualTokens: 10)

        // With the real cost booked, the next 900-token prompt fits the same minute.
        _ = try await limiter.acquire(estimatedTokens: 900)
        #expect(clock.now.timeIntervalSince1970 == 0)
    }

    @Test func exhaustedDailyQuotaThrowsInsteadOfWaiting() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let limiter = makeLimiter(.init(rpm: 100, tpm: 100_000, rpd: 2), clock: clock)

        _ = try await limiter.acquire(estimatedTokens: 1)
        _ = try await limiter.acquire(estimatedTokens: 1)

        await #expect(throws: TranslationError.quotaExhausted) {
            _ = try await limiter.acquire(estimatedTokens: 1)
        }
    }

    @Test func dailyCounterSurvivesARestartAndResetsOnANewDay() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let limits = GeminiRateLimiter.Limits(rpm: 100, tpm: 100_000, rpd: 2)

        _ = try await makeLimiter(limits, clock: clock, defaults: defaults).acquire(estimatedTokens: 1)

        // A fresh instance on the same defaults stands in for a restart: the day's usage must survive the process.
        let afterRestart = makeLimiter(limits, clock: clock, defaults: defaults)
        _ = try await afterRestart.acquire(estimatedTokens: 1)
        await #expect(throws: TranslationError.quotaExhausted) {
            _ = try await afterRestart.acquire(estimatedTokens: 1)
        }

        clock.advance(60 * 60 * 24)
        _ = try await afterRestart.acquire(estimatedTokens: 1)
        #expect(await afterRestart.quotaUsage().used == 1)
    }

    @Test func tokenEstimateOvershootsRatherThanUndershoots() {
        // Undershooting spends budget the limiter thinks it still has — the failure mode that produces 429s.
        #expect(GeminiRateLimiter.estimateTokens("") == 1)
        #expect(GeminiRateLimiter.estimateTokens(String(repeating: "a", count: 400)) == 100)
    }
}
