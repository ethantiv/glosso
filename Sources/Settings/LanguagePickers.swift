import SwiftUI

/// The primary/second pair, shared by the menu-bar menu and the Settings form — the "Automatic" tag,
/// the counterpart-filter rule and the labels must not be maintained in two hand-synced copies.
struct LanguagePickers: View {
    @Bindable var store: SettingsStore

    var body: some View {
        Picker(loc("Język główny", "Primary language"), selection: $store.primaryLanguage) {
            ForEach(PrimaryLanguage.allCases, id: \.self) { language in
                Text(language.displayName).tag(language)
            }
        }
        Picker(loc("Drugi język", "Second language"), selection: $store.secondLanguage) {
            Text(loc("Automatyczny", "Automatic")).tag(SecondLanguage?.none)
            ForEach(SecondLanguage.allCases.filter { $0 != store.primaryLanguage.asSecond }, id: \.self) { language in
                Text(language.displayName).tag(SecondLanguage?.some(language))
            }
        }
    }
}
