import Testing
import CoreGraphics
@testable import Glosso

@Suite struct FixReasonLayoutTests {
    @Test func reasonPaneCapsAtMax() {
        #expect(FixReasonLayout.reasonPaneHeight(content: 5000) == FixReasonLayout.maxReason)
        #expect(FixReasonLayout.reasonPaneHeight(content: 120) == 120)
    }
}
