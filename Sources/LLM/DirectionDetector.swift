import Foundation
import NaturalLanguage

enum DirectionDetector {
    static func detect(_ text: String, primary: PrimaryLanguage, second: SecondLanguage?) -> TranslationDirection {
        let recognizer = NLLanguageRecognizer()
        let candidates = second.map { [$0] }
            ?? SecondLanguage.allCases.filter { $0 != primary.asSecond }
        let constraints = [primary.nl] + candidates.map(\.nl)
        recognizer.languageConstraints = constraints
        recognizer.processString(text)
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
