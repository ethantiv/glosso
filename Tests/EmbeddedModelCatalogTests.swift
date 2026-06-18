import Foundation
import Testing
@testable import Glosso

@Suite struct EmbeddedModelCatalogTests {
    private func gib(_ count: Double) -> UInt64 { UInt64(count * 1_073_741_824) }

    // The tier picked at each RAM boundary is load-bearing: the model stays resident
    // and shares unified memory with the GPU, so a too-large pick starves other apps.
    // Pinning the exact tag at each threshold also fails loudly if `models` is ever
    // reordered (recommended(_:) indexes it positionally, assuming smallest→largest).
    @Test func recommendsBySpeedAccuracyTierForRAM() {
        #expect(EmbeddedModelCatalog.recommended(forRAMBytes: gib(16)).id == "gemma4:12b-mlx")
        #expect(EmbeddedModelCatalog.recommended(forRAMBytes: gib(23)).id == "gemma4:12b-mlx")
        #expect(EmbeddedModelCatalog.recommended(forRAMBytes: gib(24)).id == "gemma4:26b-mlx")
        #expect(EmbeddedModelCatalog.recommended(forRAMBytes: gib(31)).id == "gemma4:26b-mlx")
        #expect(EmbeddedModelCatalog.recommended(forRAMBytes: gib(32)).id == "gemma4:31b-mlx")
        #expect(EmbeddedModelCatalog.recommended(forRAMBytes: gib(64)).id == "gemma4:31b-mlx")
    }
}
