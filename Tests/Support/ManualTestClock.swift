import Foundation

/// Advances only when the test says so; real time is reserved for the suite's hang watchdog.
actor ManualTestClock {
    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }
    private var instant: Duration = .zero
    private var sleepers: [UUID: Sleeper] = [:]
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var cancellations = 0

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepers[id] = Sleeper(deadline: instant + duration, continuation: continuation)
                notifyObservers()
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    func waitForSleepers(_ count: Int) async {
        if sleepers.count >= count { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }
    func advance(by duration: Duration) {
        instant += duration
        let due = sleepers.filter { $0.value.deadline <= instant }
        for (id, sleeper) in due { sleepers.removeValue(forKey: id); sleeper.continuation.resume() }
    }
    private func cancel(_ id: UUID) {
        guard let sleeper = sleepers.removeValue(forKey: id) else { return }
        cancellations += 1
        sleeper.continuation.resume(throwing: CancellationError())
    }
    private func notifyObservers() {
        let ready = observers.filter { sleepers.count >= $0.0 }
        observers.removeAll { sleepers.count >= $0.0 }
        ready.forEach { $0.1.resume() }
    }
}
