import Foundation
import Testing
@testable import Glosso

@Suite struct OllamaLiveTests {
    private func ollamaReachable() async -> Bool {
        guard let url = URL(string: "http://localhost:11434/api/version") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    @Test func translatesAgainstLiveOllama() async throws {
        guard await ollamaReachable() else { return }

        let client = OllamaClient()
        var output = ""
        for try await event in client.run("Dzień dobry", action: .translate, model: LLMConfig.default.model, second: .english, formality: .automatic, humanize: false) {
            if case let .token(value) = event {
                output += value
            }
        }

        #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func explainsAgainstLiveOllama() async throws {
        guard await ollamaReachable() else { return }

        let client = OllamaClient()
        let explanation = try await client.explain(
            word: "przeszłość", in: "die Vergangenheit", source: "przeszłość",
            second: .german, model: LLMConfig.default.model)

        #expect(!explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
