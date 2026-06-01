import AppKit

@MainActor
final class SystemPasteboardReader: PasteboardReading {
    private let pasteboard = NSPasteboard.general

    var currentChangeCount: Int { pasteboard.changeCount }

    func readSelection(baselineChangeCount: Int) throws -> String {
        try SelectionGuard.validate(
            currentChangeCount: pasteboard.changeCount,
            baselineChangeCount: baselineChangeCount,
            string: pasteboard.string(forType: .string)
        )
    }
}
