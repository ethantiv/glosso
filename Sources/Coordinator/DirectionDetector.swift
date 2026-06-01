import Foundation
import NaturalLanguage

/// Picks the UI arrow only. The actual swap lives in the prompt, so this must
/// mirror it: Polish input is translated to the second language, everything
/// else to Polish.
enum DirectionDetector {
    static func detect(_ text: String, second: SecondLanguage) -> TranslationDirection {
        let recognizer = NLLanguageRecognizer()
        // The tool only ever swaps PL↔(second language), so constrain the
        // recognizer to those two. Unconstrained it routinely misreads short
        // Polish as another Slavic language, which flips the arrow against what
        // the prompt actually does.
        recognizer.languageConstraints = [.polish, nlLanguage(for: second)]
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return .unknown }
        return language == .polish ? .fromPolish(second) : .toPolish(second)
    }

    private static func nlLanguage(for second: SecondLanguage) -> NLLanguage {
        switch second {
        case .english: .english
        case .german: .german
        case .russian: .russian
        case .spanish: .spanish
        case .dutch: .dutch
        }
    }
}
