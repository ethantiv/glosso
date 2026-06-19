import Testing
import CoreGraphics
@testable import Glosso

// The reason these matter: the grammar-fix "why" dropdown was clipped because the
// window reserved less space than the dropdown actually needed (#73). The fix only
// holds if the reserve is never smaller than the rendered height for the same
// measured reason — otherwise a long reason spills past the window and clips again.
@Suite struct FixReasonLayoutTests {
    // The core no-clip invariant, swept across every plausible measured height
    // including 0 (not yet measured) and far past the cap (a runaway reason).
    @Test func reserveNeverSmallerThanRenderedDropdown() {
        for content in stride(from: CGFloat(0), through: 1200, by: 7) {
            let reserved = FixReasonLayout.estimatedDropdownHeight(content: content, loading: false)
            let actual = FixReasonLayout.actualDropdownHeight(content: content)
            #expect(reserved >= actual, "clips at content=\(content): reserved \(reserved) < actual \(actual)")
        }
    }

    // A pathologically long reason must scroll, not grow the window without bound:
    // the pane is capped so the window never exceeds the cap plus the header.
    @Test func reasonPaneCapsAtMax() {
        #expect(FixReasonLayout.reasonPaneHeight(content: 5000) == FixReasonLayout.maxReason)
        #expect(FixReasonLayout.reasonPaneHeight(content: 120) == 120)
    }

    // While loading, the reserve covers the spinner row; once measured, it tracks
    // the reason — so the window grows as the reason lands rather than clipping it.
    @Test func loadingReservesSpinnerThenTracksReason() {
        let loading = FixReasonLayout.estimatedDropdownHeight(content: 0, loading: true)
        #expect(loading == FixReasonLayout.header + FixReasonLayout.loadingPane)
        let landed = FixReasonLayout.estimatedDropdownHeight(content: 260, loading: false)
        #expect(landed == FixReasonLayout.header + 260)
    }
}
