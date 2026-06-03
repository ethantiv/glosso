import Foundation

enum SelectionGuard {
    static func validate(currentChangeCount: Int, baselineChangeCount: Int, string: String?) throws -> String {
        guard currentChangeCount > baselineChangeCount else { throw CaptureError.nothingSelected }
        return try nonEmptyText(string)
    }

    static func nonEmptyText(_ string: String?) throws -> String {
        let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let s = trimmed, !s.isEmpty else { throw CaptureError.emptyOrNonText }
        return s
    }
}
