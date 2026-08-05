import AppKit
import Foundation
import Testing
@testable import Glosso

@MainActor
@Suite("Reader toolbar")
struct ReaderToolbarTests {
    @Test("segment indexes map to the mode the page is told to show, both ways")
    func modeMapsToSegmentIndex() {
        #expect(ReaderMode(segmentIndex: 0) == .translated)
        #expect(ReaderMode(segmentIndex: 1) == .original)
        // Out of range can only come from a control that grew a segment; showing the translation is the safe read.
        #expect(ReaderMode(segmentIndex: 7) == .translated)
        #expect(ReaderMode.translated.jsValue == "translated")
        #expect(ReaderMode.original.jsValue == "original")
    }

    @Test("every default toolbar identifier builds an item, and every item is named for VoiceOver")
    func toolbarBuildsEveryDefaultItem() {
        let defaults = UserDefaults(suiteName: "ReaderToolbarTests-\(UUID().uuidString)")!
        let controller = ReaderController(llm: FakeLLMClient(), settings: SettingsStore(defaults: defaults))
        let proxy = ReaderToolbarProxy(controller: controller)
        let toolbar = NSToolbar(identifier: "test")

        for identifier in ReaderToolbarProxy.itemIdentifiers where !identifier.rawValue.hasPrefix("NSToolbar") {
            let item = proxy.toolbar(toolbar, itemForItemIdentifier: identifier, willBeInsertedIntoToolbar: false)
            #expect(item != nil, "no item for \(identifier.rawValue)")
            #expect(item?.label.isEmpty == false, "\(identifier.rawValue) has no accessibility label")
        }
    }
}
