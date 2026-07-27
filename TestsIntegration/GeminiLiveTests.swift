import Foundation
import Testing
@testable import Glosso

/// Hits the real Gemini API; silently skips with no key configured, so the suite stays green without the cloud.
@Suite struct GeminiLiveTests {
    private var apiKey: String? {
        let stored = APIKeyStore.read()?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }
        let env = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (env?.isEmpty == false) ? env : nil
    }

    private func makeClient(_ key: String) -> GeminiClient {
        GeminiClient(
            limiter: GeminiRateLimiter(store: DefaultsRef(UserDefaults(suiteName: UUID().uuidString)!)),
            keyProvider: { key }
        )
    }

    @Test func translatesAgainstLiveGemini() async throws {
        guard let apiKey else { return }

        var output = ""
        for try await event in makeClient(apiKey).run("Dzień dobry", action: .translate, model: CloudModelCatalog.default.id, primary: .polish, second: .english, formality: .automatic, style: false) {
            if case let .token(value) = event { output += value }
        }

        #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func translatesABlockAgainstLiveGemini() async throws {
        guard let apiKey else { return }

        let result = try await makeClient(apiKey).translateBlock(
            html: "<p>Good morning, everyone.</p>", into: .polish, model: CloudModelCatalog.default.id)
        #expect(result.contains("<p>"))
    }

    /// The catalog hardcodes model ids; this is what catches Google renaming them.
    @Test func catalogModelsAreServedByTheAPI() async throws {
        guard let apiKey else { return }

        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000")!)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        // With a key in hand, anything but 200 is a real failure — returning early would hide a broken listing.
        try #require((response as? HTTPURLResponse)?.statusCode == 200)

        struct Listing: Decodable {
            struct Model: Decodable { var name: String; var outputTokenLimit: Int? }
            var models: [Model]
        }
        let listing = try JSONDecoder().decode(Listing.self, from: data)
        let served = Dictionary(
            listing.models.map { ($0.name.replacingOccurrences(of: "models/", with: ""), $0.outputTokenLimit) },
            uniquingKeysWith: { first, _ in first })

        for entry in CloudModelCatalog.models {
            let reported = try #require(served[entry.id], "\(entry.id) is not served by the API any more")
            let limit = try #require(reported, "\(entry.id) reports no outputTokenLimit")
            // maxOutputTokens is clamped to this constant; above the model's own ceiling the API rejects every capped call.
            #expect(GeminiClient.outputTokenLimit <= limit,
                    "\(entry.id) allows \(limit) output tokens, we clamp to \(GeminiClient.outputTokenLimit)")
        }
    }
}
