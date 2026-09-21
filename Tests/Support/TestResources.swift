import AppKit
import Foundation

/// Removes its own preference domain when the last test reference is released.
final class TestDefaults: UserDefaults, @unchecked Sendable {
    private let domain: String
    init() {
        domain = "GlossoTests-" + UUID().uuidString
        super.init(suiteName: domain)!
    }
    deinit { removePersistentDomain(forName: domain) }
}

final class TestDirectory: Sendable {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("GlossoTests-" + UUID().uuidString)
    deinit { try? FileManager.default.removeItem(at: url) }
}

@MainActor
final class TestPasteboard {
    let value = NSPasteboard.withUniqueName()
    isolated deinit { value.releaseGlobally() }
}
