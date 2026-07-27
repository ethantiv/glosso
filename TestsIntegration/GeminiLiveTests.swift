import Foundation
import Testing
@testable import Glosso

/// Hits the real Gemini API. Silently skips when no key is configured, so the
/// suite stays green on machines that never opted into the cloud.
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
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }

        struct Listing: Decodable {
            struct Model: Decodable { var name: String; var outputTokenLimit: Int? }
            var models: [Model]
        }
        let listing = try JSONDecoder().decode(Listing.self, from: data)
        let served = Set(listing.models.map { $0.name.replacingOccurrences(of: "models/", with: "") })

        for entry in CloudModelCatalog.models {
            #expect(served.contains(entry.id), "\(entry.id) is not served by the API any more")
        }
        // The output cap we clamp maxOutputTokens to must not exceed what the model allows.
        for model in listing.models where served.contains(model.name.replacingOccurrences(of: "models/", with: "")) {
            guard CloudModelCatalog.models.contains(where: { model.name.hasSuffix($0.id) }),
                  let limit = model.outputTokenLimit else { continue }
            #expect(GeminiClient.outputTokenLimit <= limit)
        }
    }
}
