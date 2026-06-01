import Foundation
@testable import TranslatorMenuBar

@MainActor
final class FakeLoginItem: LoginItemManaging {
    var isEnabled: Bool
    private(set) var setEnabledCalls: [Bool] = []
    /// When set, `setEnabled` throws it *without* changing `isEnabled` — so a test
    /// can assert the store reverts its toggle when registration fails.
    var setEnabledError: (any Error)?

    init(isEnabled: Bool = false) { self.isEnabled = isEnabled }

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCalls.append(enabled)
        if let setEnabledError { throw setEnabledError }
        isEnabled = enabled
    }
}
