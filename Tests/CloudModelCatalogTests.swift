import Foundation
import Testing
@testable import Glosso

@Suite struct CloudModelCatalogTests {
    @Test func defaultIsTheFlashLiteEntry() {
        #expect(CloudModelCatalog.default.id == "gemini-3.5-flash-lite")
        // Catches the name lookup falling through to models[0] after a rename.
        #expect(CloudModelCatalog.models.contains(CloudModelCatalog.default))
    }

    @Test func everyEntryCarriesItsOwnFreeTierLimits() {
        #expect(CloudModelCatalog.limits(for: "gemini-3.5-flash-lite") == .init(rpm: 15, tpm: 250_000, rpd: 500))
        #expect(CloudModelCatalog.limits(for: "gemma-4-26b-a4b-it") == .init(rpm: 30, tpm: 16_000, rpd: 14_400))
        #expect(CloudModelCatalog.limits(for: "gemma-4-31b-it") == .init(rpm: 30, tpm: 16_000, rpd: 14_400))
    }

    @Test func unknownModelResolvesToTheDefaultLimits() {
        #expect(CloudModelCatalog.limits(for: "not-a-model") == CloudModelCatalog.default.limits)
    }

    @Test func modelIDsAreUnique() {
        // The id keys both the limits lookup and the limiter's per-model quota buckets.
        #expect(Set(CloudModelCatalog.models.map(\.id)).count == CloudModelCatalog.models.count)
    }
}
