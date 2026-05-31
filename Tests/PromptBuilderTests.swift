import Testing
@testable import TranslatorMenuBar

@Suite struct PromptBuilderTests {
    @Test func includesInstructionAndEndsWithInput() {
        let text = "Cześć świecie"
        let prompt = PromptBuilder.build(for: text)

        #expect(prompt.contains("translate it to English"))
        #expect(prompt.contains("Output ONLY the translation"))
        #expect(prompt.hasSuffix(text))
    }

    @Test func separatesInstructionFromInputWithBlankLine() {
        let prompt = PromptBuilder.build(for: "Hello")
        #expect(prompt == PromptBuilder.instruction + "\n\nHello")
    }
}
