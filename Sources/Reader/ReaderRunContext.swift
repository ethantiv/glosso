import Foundation

struct ReaderRunContext: Sendable {
    let id: UUID
    let primary: PrimaryLanguage
    let provider: LLMProvider
    let model: String
    let localModel: String

    @MainActor init(settings: SettingsStore) {
        id = UUID()
        primary = settings.primaryLanguage
        provider = settings.provider
        model = settings.activeModel
        localModel = settings.modelName
    }

    func engineLabel(localFallback: Bool) -> String {
        let provider = localFallback ? LLMProvider.local : provider
        return "\(provider.displayName) · \(localFallback ? localModel : model)"
    }
}

struct ReaderRun: Sendable {
    let context: ReaderRunContext
    let client: any LLMClient
}
