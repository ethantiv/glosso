import Testing
import CoreGraphics
@testable import Glosso

@Suite struct FixReasonLayoutTests {
    @Test func reserveNeverSmallerThanRenderedDropdown() {
        for content in stride(from: CGFloat(0), through: 1200, by: 7) {
            let reserved = FixReasonLayout.estimatedDropdownHeight(content: content, loading: false)
            let actual = FixReasonLayout.actualDropdownHeight(content: content)
            #expect(reserved >= actual, "clips at content=\(content): reserved \(reserved) < actual \(actual)")
        }
    }

    @Test func reasonPaneCapsAtMax() {
        #expect(FixReasonLayout.reasonPaneHeight(content: 5000) == FixReasonLayout.maxReason)
        #expect(FixReasonLayout.reasonPaneHeight(content: 120) == 120)
    }

    @Test func loadingReservesSpinnerThenTracksReason() {
        let loading = FixReasonLayout.estimatedDropdownHeight(content: 0, loading: true)
        #expect(loading == FixReasonLayout.header + FixReasonLayout.loadingPane)
        let landed = FixReasonLayout.estimatedDropdownHeight(content: 260, loading: false)
        #expect(landed == FixReasonLayout.header + 260)
    }
}
