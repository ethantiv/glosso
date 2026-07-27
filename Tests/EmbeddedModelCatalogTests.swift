import Foundation
import Testing
@testable import Glosso

@Suite struct EmbeddedModelCatalogTests {
    private func gib(_ count: Double) -> UInt64 { UInt64(count * 1_073_741_824) }

    @Test func recommendsBySpeedAccuracyTierForRAM() {
        #expect(EmbeddedModelCatalog.recommended(forRAMBytes: gib(16)).id == "gemma4:12b-mlx")
        #expect(EmbeddedModelCatalog.recommended(forRAMBytes: gib(35)).id == "gemma4:12b-mlx")
        // A 36 GB Mac lands on 26B (the empirically calibrated sweet spot), not 31B.
        #expect(EmbeddedModelCatalog.recommended(forRAMBytes: gib(36)).id == "gemma4:26b-mlx")
        #expect(EmbeddedModelCatalog.recommended(forRAMBytes: gib(47)).id == "gemma4:26b-mlx")
        #expect(EmbeddedModelCatalog.recommended(forRAMBytes: gib(48)).id == "gemma4:31b-mlx")
        #expect(EmbeddedModelCatalog.recommended(forRAMBytes: gib(64)).id == "gemma4:31b-mlx")
    }
}
