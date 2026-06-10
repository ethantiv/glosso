import CoreGraphics
import Testing
@testable import Glosso

@Suite("PanelResize")
struct PanelResizeTests {
    let start = CGSize(width: 600, height: 200)
    let minSize = CGSize(width: 400, height: 150)

    @Test("dragging the grip right and down grows the window size")
    func growsWithDrag() {
        let size = PanelResize.size(
            startSize: start,
            translation: CGSize(width: 50, height: 30),
            minSize: minSize
        )
        #expect(size == CGSize(width: 650, height: 230))
    }

    @Test("shrinking clamps at the minimum size so the card layout never collapses")
    func clampsAtMinimumSize() {
        let size = PanelResize.size(
            startSize: start,
            translation: CGSize(width: -500, height: -500),
            minSize: minSize
        )
        #expect(size == minSize)
    }
}
