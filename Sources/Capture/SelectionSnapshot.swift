import ApplicationServices
import Foundation

/// Main-actor confined: retains the actual AX element, not just the application's PID.
@MainActor
struct SelectionSnapshot {
    let pid: pid_t
    let element: CFTypeRef
    let range: NSRange
    let text: String

    func matches(_ current: SelectionSnapshot?, frontmostPID: pid_t?) -> Bool {
        guard let current, pid == frontmostPID, current.pid == pid,
              range.length > 0, range == current.range, text == current.text else { return false }
        return CFEqual(element, current.element)
    }
}

/// A stream must explicitly finish before it can overwrite the user's selection.
struct ReplacementOutput {
    private(set) var text = ""
    private var completed = false
    private var invalid = false
    mutating func receive(_ event: TranslationEvent) {
        if completed { invalid = true }
        switch event {
        case .token(let token): text += token
        case .finished(let reason):
            completed = true
            if let reason, reason != "stop" { invalid = true }
        }
    }
    var completeText: String? {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return completed && !invalid && !result.isEmpty ? result : nil
    }
}
