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
        _ limits: @escaping @Sendable (String) -> GeminiRateLimiter.Limits,
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

    private func makeLimiter(
        _ limits: GeminiRateLimiter.Limits,
        clock: FakeClock,
        defaults: UserDefaults? = nil
    ) -> GeminiRateLimiter {
        makeLimiter({ _ in limits }, clock: clock, defaults: defaults)
    }

    @Test func requestsBeyondRPMWaitForTheWindowToRoll() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let limiter = makeLimiter(.init(rpm: 2, tpm: 100_000, rpd: 1000), clock: clock)

        _ = try await limiter.acquire(estimatedTokens: 1, model: "m")
        _ = try await limiter.acquire(estimatedTokens: 1, model: "m")
        #expect(clock.now.timeIntervalSince1970 == 0)

        // The third has no slot left, so it must sit out the rest of the minute.
        _ = try await limiter.acquire(estimatedTokens: 1, model: "m")
        #expect(clock.now.timeIntervalSince1970 >= 60)
    }

    @Test func requestsBeyondTPMWaitEvenWhenRequestSlotsRemain() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let limiter = makeLimiter(.init(rpm: 100, tpm: 1000, rpd: 1000), clock: clock)

        _ = try await limiter.acquire(estimatedTokens: 900, model: "m")
        #expect(clock.now.timeIntervalSince1970 == 0)

        _ = try await limiter.acquire(estimatedTokens: 900, model: "m")
        #expect(clock.now.timeIntervalSince1970 >= 60)
    }

    @Test func promptLargerThanTheWholeBudgetStillGoesThrough() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let limiter = makeLimiter(.init(rpm: 100, tpm: 1000, rpd: 1000), clock: clock)

        // Nothing would ever make room for it, and blocking forever would kill the reader's chat on long articles.
        _ = try await limiter.acquire(estimatedTokens: 5000, model: "m")
        #expect(clock.now.timeIntervalSince1970 == 0)
    }

    @Test func settleReplacesTheEstimateWithTheReportedCount() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let limiter = makeLimiter(.init(rpm: 100, tpm: 1000, rpd: 1000), clock: clock)

        let ticket = try await limiter.acquire(estimatedTokens: 900, model: "m")
        await limiter.settle(ticket: ticket, actualTokens: 10)

        // With the real cost booked, the next 900-token prompt fits the same minute.
        _ = try await limiter.acquire(estimatedTokens: 900, model: "m")
        #expect(clock.now.timeIntervalSince1970 == 0)
    }

    @Test func exhaustedDailyQuotaThrowsInsteadOfWaiting() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let limiter = makeLimiter(.init(rpm: 100, tpm: 100_000, rpd: 2), clock: clock)

        _ = try await limiter.acquire(estimatedTokens: 1, model: "m")
        _ = try await limiter.acquire(estimatedTokens: 1, model: "m")

        await #expect(throws: TranslationError.quotaExhausted) {
            _ = try await limiter.acquire(estimatedTokens: 1, model: "m")
        }
    }

    @Test func dailyCounterSurvivesARestartAndResetsOnANewDay() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let limits = GeminiRateLimiter.Limits(rpm: 100, tpm: 100_000, rpd: 2)

        _ = try await makeLimiter(limits, clock: clock, defaults: defaults).acquire(estimatedTokens: 1, model: "m")

        // A fresh instance on the same defaults stands in for a restart: the day's usage must survive the process.
        let afterRestart = makeLimiter(limits, clock: clock, defaults: defaults)
        _ = try await afterRestart.acquire(estimatedTokens: 1, model: "m")
        await #expect(throws: TranslationError.quotaExhausted) {
            _ = try await afterRestart.acquire(estimatedTokens: 1, model: "m")
        }

        clock.advance(60 * 60 * 24)
        _ = try await afterRestart.acquire(estimatedTokens: 1, model: "m")
        #expect(await afterRestart.quotaUsage(model: "m").used == 1)
    }

    @Test func perModelDailyCountersDoNotShareABucket() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        // Flash Lite's 500/day next to Gemma's 14 400: one shared bucket would let the roomy model close the tight one.
        let limiter = makeLimiter({ $0 == "tight" ? .init(rpm: 100, tpm: 100_000, rpd: 1) : .init(rpm: 100, tpm: 100_000, rpd: 50) },
                                  clock: clock)

        _ = try await limiter.acquire(estimatedTokens: 1, model: "tight")
        await #expect(throws: TranslationError.quotaExhausted) {
            _ = try await limiter.acquire(estimatedTokens: 1, model: "tight")
        }

        _ = try await limiter.acquire(estimatedTokens: 1, model: "roomy")
        #expect(await limiter.quotaUsage(model: "roomy").used == 1)
    }

    @Test func switchingModelsMidMinuteDoesNotStallOnTheOtherModelsWindow() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let limiter = makeLimiter(.init(rpm: 1, tpm: 100_000, rpd: 1000), clock: clock)

        _ = try await limiter.acquire(estimatedTokens: 1, model: "a")

        // A shared window would make this sit out the rest of a minute it never spent.
        _ = try await limiter.acquire(estimatedTokens: 1, model: "b")
        #expect(clock.now.timeIntervalSince1970 == 0)
    }

    @Test func aCancelledWaitGivesTheDailyCountBack() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let limiter = GeminiRateLimiter(
            limits: { _ in .init(rpm: 1, tpm: 100_000, rpd: 500) },
            store: DefaultsRef(UserDefaults(suiteName: UUID().uuidString)!),
            now: { clock.now },
            sleep: { _ in throw CancellationError() }
        )

        _ = try await limiter.acquire(estimatedTokens: 1, model: "m")

        // The second has no slot this minute, so it waits — and a dismissed popup cancels the wait.
        await #expect(throws: CancellationError.self) {
            _ = try await limiter.acquire(estimatedTokens: 1, model: "m")
        }

        // Charging it would spend a request Google never saw, which on a 500/day model is real money.
        #expect(await limiter.quotaUsage(model: "m").used == 1)
    }

    @Test func quotaUsageReportsTheSelectedModelsLimit() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let limiter = makeLimiter({ $0 == "tight" ? .init(rpm: 100, tpm: 100_000, rpd: 500) : .init(rpm: 100, tpm: 100_000, rpd: 14_400) },
                                  clock: clock)

        _ = try await limiter.acquire(estimatedTokens: 1, model: "tight")

        #expect(await limiter.quotaUsage(model: "tight") == (used: 1, limit: 500))
        #expect(await limiter.quotaUsage(model: "roomy") == (used: 0, limit: 14_400))
    }

    @Test func tokenEstimateOvershootsRatherThanUndershoots() {
        // Undershooting spends budget the limiter thinks it still has — the failure mode that produces 429s.
        #expect(GeminiRateLimiter.estimateTokens("") == 1)
        #expect(GeminiRateLimiter.estimateTokens(String(repeating: "a", count: 400)) == 100)
    }
}
