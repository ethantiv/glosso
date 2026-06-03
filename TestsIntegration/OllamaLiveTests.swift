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
        for try await event in client.translate("Dzień dobry", model: LLMConfig.default.model, second: .english, formality: .automatic) {
            if case let .token(value) = event {
                output += value
            }
        }

        #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
