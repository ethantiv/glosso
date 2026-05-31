import Foundation
import NaturalLanguage

/// Picks the UI arrow only. The actual swap lives in the prompt, so this must
/// mirror it: Polish input is translated to English, everything else to Polish.
enum DirectionDetector {
    static func detect(_ text: String) -> TranslationDirection {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return .unknown }
        return language == .polish ? .plToEn : .enToPl
    }
}
