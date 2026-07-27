import Foundation

/// The prompt layer, shared by every engine: a backend implements `GenerationBackend` and gets every `LLMClient` method for free.
extension LLMClient where Self: GenerationBackend {
    /// Reader calls generate whole articles block by block; 60s is not enough.
    static var longFormTimeout: TimeInterval { 300 }

    func run(_ text: String, action: Action, model: String, primary: PrimaryLanguage, second: SecondLanguage, formality: Formality, style: Bool) -> AsyncThrowingStream<TranslationEvent, Error> {
        streamGeneration(prompt: PromptBuilder.build(for: text, action: action, primary: primary, second: second, formality: formality, style: style), model: model)
    }

    func reword(original: String, to chosen: String, in translation: String, source: String, primary: PrimaryLanguage, second: SecondLanguage, formality: Formality, model: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        streamGeneration(prompt: PromptBuilder.buildReword(original: original, chosen: chosen, translation: translation, source: source, primary: primary, second: second, formality: formality), model: model)
    }

    func alternatives(for word: String, in translation: String, source: String, primary: PrimaryLanguage, second: SecondLanguage, model: String) async throws -> [String] {
        let prompt = PromptBuilder.buildAlternatives(word: word, translation: translation, source: source, primary: primary, second: second)
        return AlternativesParser.parse(try await generate(prompt: prompt, model: model, timeout: nil, numPredict: nil), original: word)
    }

    func reply(to text: String, model: String) async throws -> [String] {
        let prompt = PromptBuilder.buildReply(text: text)
        return ReplyParser.parse(try await generate(prompt: prompt, model: model, timeout: nil, numPredict: nil))
    }

    func translateBlock(html: String, into primary: PrimaryLanguage, model: String) async throws -> String {
        let cap = max(256, html.utf8.count)
        return try await generate(prompt: PromptBuilder.buildBlockTranslation(html: html, into: primary),
                                  model: model, timeout: Self.longFormTimeout, numPredict: cap)
    }

    func readerSummary(of text: String, into primary: PrimaryLanguage, model: String) async throws -> String {
        try await generate(prompt: PromptBuilder.buildReaderSummary(text: text, into: primary),
                           model: model, timeout: Self.longFormTimeout, numPredict: 512)
    }

    func askArticle(question: String, history: [(question: String, answer: String)], article: String, into primary: PrimaryLanguage, model: String) async throws -> String {
        try await generate(prompt: PromptBuilder.buildAskArticle(question: question, history: history, article: article, into: primary),
                           model: model, timeout: Self.longFormTimeout, numPredict: 1024)
    }

    func articleQuestions(about article: String, into primary: PrimaryLanguage, model: String) async throws -> [String] {
        let raw = try await generate(prompt: PromptBuilder.buildArticleQuestions(article: article, into: primary),
                                     model: model, timeout: Self.longFormTimeout, numPredict: 256)
        return Array(AlternativesParser.parse(raw, original: "").prefix(5))
    }

    func explain(word: String, in translation: String, source: String, primary: PrimaryLanguage, second: SecondLanguage, model: String) async throws -> String {
        let prompt = PromptBuilder.buildExplain(word: word, translation: translation, source: source, primary: primary, second: second)
        return ExplanationParser.clean(try await generate(prompt: prompt, model: model, timeout: nil, numPredict: nil))
    }

    func explainFix(error: String, correction: String, original: String, corrected: String, primary: PrimaryLanguage, second: SecondLanguage, englishRules: Bool, style: Bool, model: String) async throws -> String {
        let prompt = PromptBuilder.buildExplainFix(error: error, correction: correction, original: original, corrected: corrected, primary: primary, second: second, englishRules: englishRules, style: style)
        return ExplanationParser.clean(try await generate(prompt: prompt, model: model, timeout: nil, numPredict: nil))
    }

    func explainRegister(previous: String, current: String, from: Formality, to: Formality, source: String, primary: PrimaryLanguage, second: SecondLanguage, model: String) async throws -> String {
        let prompt = PromptBuilder.buildExplainRegister(previous: previous, current: current, from: from, to: to, source: source, primary: primary, second: second)
        return ExplanationParser.clean(try await generate(prompt: prompt, model: model, timeout: nil, numPredict: nil))
    }
}
