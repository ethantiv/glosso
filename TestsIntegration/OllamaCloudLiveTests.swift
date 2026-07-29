import Foundation
import Testing
@testable import Glosso

/// Hits the real Ollama Cloud; silently skips with no key configured, so the suite stays green without it.
@Suite struct OllamaCloudLiveTests {
    private var apiKey: String? {
        let stored = APIKeyStore.read(account: APIKeyStore.ollamaAccount)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let stored, !stored.isEmpty { return stored }
        let env = ProcessInfo.processInfo.environment["OLLAMA_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (env?.isEmpty == false) ? env : nil
    }

    private func makeClient(_ key: String) -> OllamaClient {
        OllamaClient(endpointProvider: { OllamaCloudCatalog.baseURL }, keyProvider: { key })
    }

    /// The whole integration rests on the cloud speaking the local engine's NDJSON. Nothing else proves it.
    @Test func translatesAgainstLiveOllamaCloud() async throws {
        guard let apiKey else { return }

        var output = ""
        for try await event in makeClient(apiKey).run("Dzień dobry", action: .translate, model: OllamaCloudCatalog.defaultModel, primary: .polish, second: .english, formality: .automatic, style: false) {
            if case let .token(value) = event { output += value }
        }

        #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// `think:false` is undocumented on the cloud host, and gemma4:31b advertises thinking. If it were rejected outright, this call would fail rather than merely run long.
    @Test func theCloudAcceptsTheLockedGenerationOptions() async throws {
        guard let apiKey else { return }

        let result = try await makeClient(apiKey).translateBlock(
            html: "<p>Good morning, everyone.</p>", into: .polish, model: OllamaCloudCatalog.defaultModel)
        #expect(result.contains("<p>"))
    }

    /// The default model id is hardcoded and Ollama retires cloud models on a published schedule.
    @Test func theDefaultModelIsStillServed() async throws {
        let lister = OllamaModelLister(endpointProvider: { OllamaCloudCatalog.baseURL })
        // This endpoint needs no key, so a failure here is a real one — not a missing-credentials skip.
        let models = try await lister.availableModels()
        #expect(models.contains(OllamaCloudCatalog.defaultModel),
                "\(OllamaCloudCatalog.defaultModel) is not served by Ollama Cloud any more")
    }
}
