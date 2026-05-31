import Foundation

enum PromptBuilder {
    static let instruction = "If the following text is in Polish, translate it to English. Otherwise, translate it to Polish. Output ONLY the translation, no explanations, no quotes."

    static func build(for text: String) -> String {
        instruction + "\n\n" + text
    }
}
