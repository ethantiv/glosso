import CoreGraphics
import Testing
@testable import Glosso

@Suite("PanelResize")
struct PanelResizeTests {
    let start = CGRect(x: 100, y: 500, width: 600, height: 200)
    let minSize = CGSize(width: 400, height: 150)

    @Test("dragging the grip right and down grows the window while the top-left stays pinned under the cursor")
    func growsDownRightFromPinnedTopLeft() {
        let frame = PanelResize.frame(
            startFrame: start,
            translation: CGSize(width: 50, height: 30),
            minSize: minSize
        )
        #expect(frame.width == 650)
        #expect(frame.height == 230)
        #expect(frame.minX == start.minX)
        #expect(frame.maxY == start.maxY)
    }

    @Test("shrinking clamps at the minimum size so the card layout never collapses")
    func clampsAtMinimumSize() {
        let frame = PanelResize.frame(
            startFrame: start,
            translation: CGSize(width: -500, height: -500),
            minSize: minSize
        )
        #expect(frame.size == minSize)
        #expect(frame.minX == start.minX)
        #expect(frame.maxY == start.maxY)
    }
}
