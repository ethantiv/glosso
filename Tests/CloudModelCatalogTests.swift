import Foundation
import Testing
@testable import Glosso

@Suite struct CloudModelCatalogTests {
    @Test func defaultIsTheAccurateGemmaEntry() {
        #expect(CloudModelCatalog.default.id == "gemma-4-31b-it")
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

    @Test func everyEntryAsksForAtLeastOneBlockPerRequest() {
        // The packer ramps up to this number and clamps with min(), so a zero or negative would
        // silently collapse every batch to one block — the reader would still work, just slower
        // than the measurement says it should, with nothing anywhere reporting the regression.
        for entry in CloudModelCatalog.models {
            #expect(entry.batch >= 1, "\(entry.id) asks for \(entry.batch) blocks per request")
        }
        #expect(OllamaCloudCatalog.batch >= 1)
    }

    @Test func unknownModelResolvesToTheDefaultBatch() {
        // Same reason as the limits lookup: the id comes from settings and the catalog moves under it.
        #expect(CloudModelCatalog.batch(for: "not-a-model") == CloudModelCatalog.default.batch)
    }

    @Test func modelIDsAreUnique() {
        // The id keys both the limits lookup and the limiter's per-model quota buckets.
        #expect(Set(CloudModelCatalog.models.map(\.id)).count == CloudModelCatalog.models.count)
    }
}
