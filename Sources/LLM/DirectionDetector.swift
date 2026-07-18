import Foundation
import NaturalLanguage

/// Single source of truth for the translation direction: it picks the UI arrow
/// AND the target language named in the translate prompt (PromptBuilder).
/// Primary-language input goes to the second language, everything else to the
/// primary; on .unknown the prompt falls back to the old conditional swap
/// instruction. A `nil` second means Automatic: the second side is whichever
/// supported language the text turns out to be — and when the text is already
/// in the primary language the target is ambiguous, so it falls back to the
/// primary's PL/EN counterpart.
enum DirectionDetector {
    static func detect(_ text: String, primary: PrimaryLanguage, second: SecondLanguage?) -> TranslationDirection {
        let recognizer = NLLanguageRecognizer()
        // Constrain the recognizer to the languages actually in play (the fixed
        // pair, or primary + all candidates under Automatic). Unconstrained it
        // routinely misreads short Polish as another Slavic language, which
        // flips the arrow against what the prompt actually does.
        let candidates = second.map { [$0] }
            ?? SecondLanguage.allCases.filter { $0 != primary.asSecond }
        let constraints = [primary.nl] + candidates.map(\.nl)
        recognizer.languageConstraints = constraints
        recognizer.processString(text)
        // Since this pick names the prompt's target (not just the arrow), a
        // misdetection would translate into the source's own language — the model
        // then echoes the text. Short PL/EN homographs ("To", "Do") are exactly
        // that case and measure ≤0.75, while correct reads measure ≥0.84 ("Hello
        // world" 0.86, "To do" 0.94; single foreign words ≥0.98 for every
        // supported pair), so below 0.8 return .unknown and let the prompt's
        // conditional swap decide. The confidence is the winner's share of the
        // constrained set's mass, not a raw hypothesis: languageHypotheses'
        // interplay with languageConstraints is undocumented (its key set is
        // unconstrained; empirically its mass does renormalize to the set), and
        // the set-relative share reads the same under either behavior.
        guard let language = recognizer.dominantLanguage else { return .unknown }
        let hypotheses = recognizer.languageHypotheses(withMaximum: 50)
        let constrainedMass = constraints.reduce(0) { $0 + (hypotheses[$1] ?? 0) }
        let winnerMass = hypotheses[language] ?? 0
        guard constrainedMass > 0, winnerMass / constrainedMass >= 0.8 else { return .unknown }
        if language == primary.nl {
            return .fromPrimary(primary, second ?? primary.counterpart.asSecond)
        }
        guard let winner = candidates.first(where: { $0.nl == language }) else { return .unknown }
        return .toPrimary(primary, winner)
    }
}

extension PrimaryLanguage {
    var nl: NLLanguage {
        switch self {
        case .polish: .polish
        case .english: .english
        }
    }
}

extension SecondLanguage {
    var nl: NLLanguage {
        switch self {
        case .english: .english
        case .german: .german
        case .russian: .russian
        case .spanish: .spanish
        case .dutch: .dutch
        case .french: .french
        case .polish: .polish
        }
    }
}
