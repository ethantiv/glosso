import Foundation
@testable import Glosso

@MainActor
final class FakeLoginItem: LoginItemManaging {
    var isEnabled: Bool
    private(set) var setEnabledCalls: [Bool] = []
    var setEnabledError: (any Error)?

    init(isEnabled: Bool = false) { self.isEnabled = isEnabled }

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCalls.append(enabled)
        if let setEnabledError { throw setEnabledError }
        isEnabled = enabled
    }
}
