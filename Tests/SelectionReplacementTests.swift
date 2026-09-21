import AppKit
import Testing
@testable import Glosso

@MainActor
@Suite(.timeLimit(.minutes(1))) struct SelectionReplacementTests {
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
        let defaults = TestDefaults()
        var messages: [String] = []
        let coordinator = AppCoordinator(llm: llm, monitor: FakeHotkeyMonitor(), reader: FakePasteboardReader(),
            axReader: ax, popup: FakePopup(), settings: SettingsStore(defaults: defaults), replacer: replacer,
            frontmostPID: { 42 }, frontmostBundleID: { "com.apple.TextEdit" }, pasteboard: pasteboard, notify: { messages.append($0) })
        await coordinator.fixGrammarInPlace(sourcePID: 42)
        #expect(replacer.replacedText == nil)
        #expect(pasteboard.changeCount == baseline)
        #expect(!messages.isEmpty)
    }

    @Test(arguments: ["cancel", "changed", "missing", "success"])
    func suspendedShortcutVerifiesTargetAndCompletion(outcome: String) async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("original clipboard", forType: .string)
        let baseline = board.changeCount
        let gate = StreamGate()
        let llm = FakeLLMClient(events: [.token("complete result"), .finished(doneReason: nil)], gate: gate)
        let ax = FakeAXSelectionReader(); ax.text = "original"
        let replacer = FakeSelectionReplacer()
        let coordinator = AppCoordinator(llm: llm, monitor: FakeHotkeyMonitor(), reader: FakePasteboardReader(),
            axReader: ax, popup: FakePopup(), settings: SettingsStore(defaults: TestDefaults()), replacer: replacer,
            frontmostPID: { 42 }, frontmostBundleID: { "com.apple.TextEdit" }, pasteboard: board, notify: { _ in })
        defer { coordinator.stop() }
        let task = Task { await coordinator.fixGrammarInPlace(sourcePID: 42) }
        await llm.streamStarted.wait()
        if outcome == "cancel" { task.cancel() }
        if outcome == "changed" { ax.text = "different selection" }
        if outcome == "missing" { ax.snapshotAvailable = false }
        gate.release()
        await task.value
        #expect(replacer.replacedText == (outcome == "success" ? "complete result" : nil))
        if outcome == "changed" || outcome == "missing" {
            #expect(board.string(forType: .string) == "complete result")
        } else {
            #expect(board.changeCount == baseline)
        }
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
        let clock = ManualTestClock()
        let replacer = SystemSelectionReplacer(pasteboard: pasteboard, restoreDelay: .milliseconds(10),
            sendKey: { _ in }, sleep: { try await clock.sleep(for: $0) })
        replacer.replace(with: "translated")
        pasteboard.clearContents()
        pasteboard.setString("translated", forType: .string)
        let userChange = pasteboard.changeCount
        await clock.waitForSleepers(1)
        await clock.advance(by: .milliseconds(10))
        await replacer.restoreTask?.value
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
        let clock = ManualTestClock()
        let replacer = SystemSelectionReplacer(pasteboard: pasteboard, restoreDelay: .milliseconds(10),
            sendKey: { _ in }, sleep: { try await clock.sleep(for: $0) })
        replacer.replace(with: "translated")
        await clock.waitForSleepers(1)
        await clock.advance(by: .milliseconds(10))
        await replacer.restoreTask?.value
        #expect(pasteboard.string(forType: .string) == "original")
        #expect(pasteboard.data(forType: .rtf) == Data([1, 2, 3]))
    }
}
