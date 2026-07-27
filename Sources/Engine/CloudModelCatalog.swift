import Foundation

/// The Gemma tiers the Gemini API serves. Both are free-only — Google's pricing
/// page lists no paid tier for Gemma, so higher limits can't be bought.
enum CloudModelCatalog {
    struct Entry: Sendable, Identifiable, Equatable {
        let id: String
        let displayName: String
        /// SF Symbol for the speed↔accuracy tier, matching EmbeddedModelCatalog.
        let icon: String
    }

    // Computed so displayName resolves in the app's current UI language.
    static var models: [Entry] { [
        Entry(id: "gemma-4-26b-a4b-it", displayName: loc("Szybki", "Fast"), icon: "gauge.with.dots.needle.67percent"),
        Entry(id: "gemma-4-31b-it", displayName: loc("Najdokładniejszy", "Most accurate"), icon: "gauge.with.dots.needle.100percent"),
    ] }

    static var `default`: Entry { models[1] }
}
