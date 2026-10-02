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
        try #require(await ollamaReachable(), "Local Ollama is required for live tests")

        let client = OllamaClient()
        var output = ""
        for try await event in client.run("Dzień dobry", action: .translate, model: LLMConfig.default.model, primary: .polish, second: .english, formality: .automatic, style: false) {
            if case let .token(value) = event {
                output += value
            }
        }

        #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func correctsProseWithoutSemicolonsAgainstLiveOllama() async throws {
        try #require(await ollamaReachable(), "Local Ollama is required for live tests")

        let cases: [(text: String, anchor: String)] = [
            ("The connection is working; I just need to update its config on the sandbox. In 30 minutes, you will be able to log in.", "30"),
            ("Polaczenie dziala; musze tylko zaktualizowac konfiguracje na sandboxie. Za 30 minut bedziesz mogl sie zalogowac.", "30"),
            ("Hej, wyslalem ci plik, sprawdz go jak bedziesz miec chwile. Spotkanie jest o 15:00.", "15:00"),
            ("The connection is working, I just need to update its config on the sandbox. In 30 minutes you can log in.", "30"),
        ]
        let client = OllamaClient()
        for style in [false, true] {
            for (text, anchor) in cases {
                var output = ""
                for try await event in client.run(
                    text, action: .fixGrammar, model: LLMConfig.default.model,
                    primary: .polish, second: .english, formality: .automatic, style: style
                ) {
                    if case let .token(value) = event { output += value }
                }

                #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!output.contains(";"), "style=\(style), input=\(text), output=\(output)")
                #expect(output.contains(anchor), "Lost a fact: \(output)")
                let recognizer = NLLanguageRecognizer()
                recognizer.languageConstraints = [.polish, .english]
                recognizer.processString(text)
                let language = recognizer.dominantLanguage
                recognizer.reset()
                recognizer.processString(output)
                #expect(recognizer.dominantLanguage == language, "Changed language: \(output)")
            }
        }
    }

    @Test func translatesDutchToPolishAgainstLiveOllama() async throws {
        try #require(await ollamaReachable(), "Local Ollama is required for live tests")

        let client = OllamaClient()
        var output = ""
        for try await event in client.run(
            "De kosten van de schade door de bever lopen snel op, vreest de Unie van Waterschappen.",
            action: .translate, model: LLMConfig.default.model, primary: .polish, second: .dutch,
            formality: .automatic, style: false
        ) {
            if case let .token(value) = event {
                output += value
            }
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.polish, .dutch, .english]
        recognizer.processString(output)
        #expect(recognizer.dominantLanguage == .polish, "expected Polish output, got: \(output)")
    }

    @Test func explainsAgainstLiveOllama() async throws {
        try #require(await ollamaReachable(), "Local Ollama is required for live tests")

        let client = OllamaClient()
        let explanation = try await client.explain(
            word: "przeszłość", in: "die Vergangenheit", source: "przeszłość",
            primary: .polish, second: .german, model: LLMConfig.default.model)

        #expect(!explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func explainsRegisterShiftAgainstLiveOllama() async throws {
        try #require(await ollamaReachable(), "Local Ollama is required for live tests")

        let client = OllamaClient()
        let note = try await client.explainRegister(
            previous: "Könnten Sie mir bitte helfen?", current: "Könntest du mir helfen?",
            from: .formal, to: .informal, source: "Czy mógłby mi Pan pomóc?",
            primary: .polish, second: .german, model: LLMConfig.default.model)

        #expect(note.contains("du"), "expected the note to name the du form, got: \(note)")
        #expect(note.contains("Sie"), "expected the note to name the Sie form, got: \(note)")
    }
}
