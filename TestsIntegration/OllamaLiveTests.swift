import Foundation
import NaturalLanguage
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
        for try await event in client.run("Dzień dobry", action: .translate, model: LLMConfig.default.model, second: .english, formality: .automatic, humanize: false, style: false) {
            if case let .token(value) = event {
                output += value
            }
        }

        #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // Regression guard for the in-code target resolution — see
    // PromptBuilder.instruction and CLAUDE.md subtlety #2 for the NL/RU rationale.
    @Test func translatesDutchToPolishAgainstLiveOllama() async throws {
        guard await ollamaReachable() else { return }

        let client = OllamaClient()
        var output = ""
        for try await event in client.run(
            "De kosten van de schade door de bever lopen snel op, vreest de Unie van Waterschappen.",
            action: .translate, model: LLMConfig.default.model, second: .dutch,
            formality: .automatic, humanize: true, style: false
        ) {
            if case let .token(value) = event {
                output += value
            }
        }

        // Constrained to the three plausible outcomes (Polish, Dutch echo, English
        // drift): DirectionDetector's two-language constraint would force an English
        // answer into one of its buckets and could pass on wrong-language output.
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.polish, .dutch, .english]
        recognizer.processString(output)
        #expect(recognizer.dominantLanguage == .polish, "expected Polish output, got: \(output)")
    }

    @Test func explainsAgainstLiveOllama() async throws {
        guard await ollamaReachable() else { return }

        let client = OllamaClient()
        let explanation = try await client.explain(
            word: "przeszłość", in: "die Vergangenheit", source: "przeszłość",
            second: .german, model: LLMConfig.default.model)

        #expect(!explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // The whole point of the register coach (#53): the note must name the concrete
    // pronoun shift a T–V language makes, not just say "the tone is now informal".
    @Test func explainsRegisterShiftAgainstLiveOllama() async throws {
        guard await ollamaReachable() else { return }

        let client = OllamaClient()
        let note = try await client.explainRegister(
            previous: "Könnten Sie mir bitte helfen?", current: "Könntest du mir helfen?",
            from: .formal, to: .informal, source: "Czy mógłby mi Pan pomóc?",
            second: .german, model: LLMConfig.default.model)

        #expect(note.contains("du"), "expected the note to name the du form, got: \(note)")
        #expect(note.contains("Sie"), "expected the note to name the Sie form, got: \(note)")
    }
}
