import Foundation

enum SelectionGuard {
    static func validate(currentChangeCount: Int, baselineChangeCount: Int, string: String?) throws -> String {
        guard currentChangeCount > baselineChangeCount else { throw CaptureError.nothingSelected }
        guard let s = string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CaptureError.emptyOrNonText }
        return s
    }
}
