import Foundation
import NaturalLanguage

/// Single source of truth for the translation direction: it picks the UI arrow
/// AND the target language named in the translate prompt (PromptBuilder). Polish
/// input goes to the second language, everything else to Polish; on .unknown the
/// prompt falls back to the old conditional swap instruction.
enum DirectionDetector {
    static func detect(_ text: String, second: SecondLanguage) -> TranslationDirection {
        let recognizer = NLLanguageRecognizer()
        // The tool only ever swaps PL↔(second language), so constrain the
        // recognizer to those two. Unconstrained it routinely misreads short
        // Polish as another Slavic language, which flips the arrow against what
        // the prompt actually does.
        recognizer.languageConstraints = [.polish, nlLanguage(for: second)]
        recognizer.processString(text)
        // Since this pick names the prompt's target (not just the arrow), a
        // misdetection would translate into the source's own language — the model
        // then echoes the text. Short PL/EN homographs ("To", "Do") are exactly
        // that case and measure ≤0.75, while correct reads measure ≥0.84 ("Hello
        // world" 0.86, "To do" 0.94; single foreign words ≥0.98 for every
        // supported pair), so below 0.8 return .unknown and let the prompt's
        // conditional swap decide. The confidence is the winner's share of the
        // constrained pair's mass, not a raw hypothesis: languageHypotheses'
        // interplay with languageConstraints is undocumented (its key set is
        // unconstrained; empirically its mass does renormalize to the pair), and
        // the pair-relative share reads the same under either behavior.
        guard let language = recognizer.dominantLanguage else { return .unknown }
        let hypotheses = recognizer.languageHypotheses(withMaximum: 50)
        let polishMass = hypotheses[.polish] ?? 0
        let secondMass = hypotheses[nlLanguage(for: second)] ?? 0
        let pairMass = polishMass + secondMass
        let winnerMass = language == .polish ? polishMass : secondMass
        guard pairMass > 0, winnerMass / pairMass >= 0.8 else { return .unknown }
        return language == .polish ? .fromPolish(second) : .toPolish(second)
    }

    private static func nlLanguage(for second: SecondLanguage) -> NLLanguage {
        switch second {
        case .english: .english
        case .german: .german
        case .russian: .russian
        case .spanish: .spanish
        case .dutch: .dutch
        case .french: .french
        }
    }
}
