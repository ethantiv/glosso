import AppKit
import Testing
@testable import Glosso

@MainActor
@Suite struct SelectionReplacementTests {
    @Test(arguments: ["pid", "element", "range", "text", "missing"])
    func changedTargetIsNeverReplaced(change: String) {
        let original = SelectionSnapshot(pid: 42, element: "editor" as NSString,
                                         range: NSRange(location: 3, length: 4), text: "word")
        let current = SelectionSnapshot(pid: change == "pid" ? 99 : 42,
            element: (change == "element" ? "other editor" : "editor") as NSString,
            range: NSRange(location: change == "range" ? 4 : 3, length: 4),
            text: change == "text" ? "next" : "word")
        #expect(!original.matches(change == "missing" ? nil : current, frontmostPID: 42))
        #expect(original.matches(original, frontmostPID: 42))
    }

    @Test(arguments: ["length", "missing", "error", "after-finish"])
    func incompleteOutputCannotReplaceOrChangeClipboard(kind: String) async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("user clipboard", forType: .string)
        let baseline = pasteboard.changeCount
        var events: [TranslationEvent] = [.token("partial")]
        if kind == "length" { events.append(.finished(doneReason: "length")) }
        if kind == "after-finish" { events += [.finished(doneReason: "stop"), .token("late")] }
        let llm = FakeLLMClient(events: events, error: kind == "error" ? .malformedStream : nil)
        let ax = FakeAXSelectionReader(); ax.text = "original"
        let replacer = FakeSelectionReplacer()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var messages: [String] = []
        let coordinator = AppCoordinator(llm: llm, monitor: FakeHotkeyMonitor(), reader: FakePasteboardReader(),
            axReader: ax, popup: FakePopup(), settings: SettingsStore(defaults: defaults), replacer: replacer,
            frontmostPID: { 42 }, pasteboard: pasteboard, notify: { messages.append($0) })
        await coordinator.fixGrammarInPlace(sourcePID: 42)
        #expect(replacer.replacedText == nil)
        #expect(pasteboard.changeCount == baseline)
        #expect(!messages.isEmpty)
    }

    @Test func ollamaExplicitFinishWithoutReasonIsComplete() {
        var output = ReplacementOutput()
        output.receive(.token("complete"))
        output.receive(.finished(doneReason: nil))
        #expect(output.completeText == "complete")
    }

    @Test func restoreDoesNotOverwriteANewCopyEvenIfTextIsIdentical() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("original", forType: .string)
        let replacer = SystemSelectionReplacer(pasteboard: pasteboard, restoreDelay: .milliseconds(10), sendKey: { _ in })
        replacer.replace(with: "translated")
        pasteboard.clearContents()
        pasteboard.setString("translated", forType: .string)
        let userChange = pasteboard.changeCount
        try await Task.sleep(for: .milliseconds(40))
        #expect(pasteboard.changeCount == userChange)
        #expect(pasteboard.string(forType: .string) == "translated")
    }

    @Test func restorePreservesAllClipboardFlavors() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("original", forType: .string)
        item.setData(Data([1, 2, 3]), forType: .rtf)
        pasteboard.writeObjects([item])
        let replacer = SystemSelectionReplacer(pasteboard: pasteboard, restoreDelay: .milliseconds(10), sendKey: { _ in })
        replacer.replace(with: "translated")
        try await Task.sleep(for: .milliseconds(40))
        #expect(pasteboard.string(forType: .string) == "original")
        #expect(pasteboard.data(forType: .rtf) == Data([1, 2, 3]))
    }
}
