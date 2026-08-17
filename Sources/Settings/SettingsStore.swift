import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let model = "llm.model"
        static let provider = "llm.provider"
        static let cloudModel = "llm.cloudModel"
        static let ollamaCloudModel = "llm.ollamaCloudModel"
        static let primaryLanguage = "app.primaryLanguage"
        static let secondLanguage = "translation.secondLanguage"
        static let formality = "translation.formality"
        static let fixChord = "shortcut.fixInPlace"
        static let translateInPlaceChord = "shortcut.translateInPlace"
        static let hasCompletedOnboarding = "app.hasCompletedOnboarding"
        static let lastNotifiedVersion = "update.lastNotifiedVersion"
    }

    /// UserDefaults sentinel for the automatic second language (`nil` in code).
    private static let autoSecond = "auto"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loginItem: any LoginItemManaging
    @ObservationIgnored private let writeAPIKey: (String) -> Bool
    @ObservationIgnored private let writeOllamaAPIKey: (String) -> Bool
    @ObservationIgnored private let readAPIKey: () -> String?
    @ObservationIgnored private let readOllamaAPIKey: () -> String?
    @ObservationIgnored private var googleKeyLoaded = false
    @ObservationIgnored private var ollamaKeyLoaded = false
    /// Set while `loadAPIKeys` seeds the two properties, so their `didSet` doesn't write what it just read back.
    @ObservationIgnored private var loadingKeys = false

    var modelName: String {
        didSet { defaults.set(modelName, forKey: Key.model) }
    }

    /// Which engine serves the prompts. Local stays the default — the cloud is opt-in because it sends the text to Google.
    var provider: LLMProvider {
        didSet { defaults.set(provider.rawValue, forKey: Key.provider) }
    }

    var cloudModel: String {
        didSet { defaults.set(cloudModel, forKey: Key.cloudModel) }
    }

    var ollamaCloudModel: String {
        didSet { defaults.set(ollamaCloudModel, forKey: Key.ollamaCloudModel) }
    }

    /// The model every LLM call must use — the three providers name models differently.
    var activeModel: String {
        switch provider {
        case .local: modelName
        case .cloud: cloudModel
        case .ollamaCloud: ollamaCloudModel
        }
    }

    /// Not UserDefaults-backed: the Keychain is the source of truth, like `launchAtLogin` deferring to SMAppService.
    /// Empty until `loadAPIKeys()` — see it for why the read can't happen in `init`.
    var apiKey: String {
        didSet {
            guard !loadingKeys, apiKey != oldValue else { return }
            if !writeAPIKey(apiKey) { Self.notifyKeySaveFailure() }
        }
    }

    var ollamaAPIKey: String {
        didSet {
            guard !loadingKeys, ollamaAPIKey != oldValue else { return }
            if !writeOllamaAPIKey(ollamaAPIKey) { Self.notifyKeySaveFailure() }
        }
    }

    /// A silently dropped key would resurface only after relaunch, as `.missingAPIKey` with no hint why.
    private static func notifyKeySaveFailure() {
        SystemUserNotifier.post(loc("Nie udało się zapisać klucza API w pęku kluczy.",
                                    "Couldn't save the API key to the Keychain."))
    }

    /// Pulls one key out of the Keychain, once, and only for the `SecureField` that is actually on screen. Nothing else
    /// needs these: `GeminiClient` and the Ollama Cloud `OllamaClient` call `APIKeyStore.read` themselves per request,
    /// so the two properties exist purely to back those fields. Reading them in `init` cost every launch two Keychain
    /// reads — and on a self-signed build, whose signature changes with every release, that is two password prompts,
    /// even on a local-engine run that shows neither field.
    func loadGoogleAPIKey() {
        guard !googleKeyLoaded else { return }
        googleKeyLoaded = true
        loadingKeys = true
        apiKey = readAPIKey() ?? ""
        loadingKeys = false
    }

    func loadOllamaAPIKey() {
        guard !ollamaKeyLoaded else { return }
        ollamaKeyLoaded = true
        loadingKeys = true
        ollamaAPIKey = readOllamaAPIKey() ?? ""
        loadingKeys = false
    }

    var primaryLanguage: PrimaryLanguage {
        didSet {
            defaults.set(primaryLanguage.rawValue, forKey: Key.primaryLanguage)
            if secondLanguage == primaryLanguage.asSecond {
                secondLanguage = primaryLanguage.counterpart.asSecond
            }
        }
    }

    /// `nil` means Automatic: the second side is detected per selection/page.
    var secondLanguage: SecondLanguage? {
        didSet { defaults.set(secondLanguage?.rawValue ?? Self.autoSecond, forKey: Key.secondLanguage) }
    }

    var formality: Formality {
        didSet { defaults.set(formality.rawValue, forKey: Key.formality) }
    }

    /// Headless "fix grammar in place" chord (issue #21), default Ctrl+Cmd+G.
    var fixChord: KeyChord {
        didSet { defaults.set(try? JSONEncoder().encode(fixChord), forKey: Key.fixChord) }
    }

    /// Headless "translate in place" chord (issue #21), default Ctrl+Cmd+T.
    var translateInPlaceChord: KeyChord {
        didSet { defaults.set(try? JSONEncoder().encode(translateInPlaceChord), forKey: Key.translateInPlaceChord) }
    }

    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    var lastNotifiedVersion: String {
        didSet { defaults.set(lastNotifiedVersion, forKey: Key.lastNotifiedVersion) }
    }

    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != loginItem.isEnabled else { return }
            do { try loginItem.setEnabled(launchAtLogin) }
            catch { launchAtLogin = oldValue }
        }
    }

    init(
        defaults: UserDefaults = .standard,
        loginItem: any LoginItemManaging = SMAppServiceLoginItem(),
        systemLanguages: [String] = Locale.preferredLanguages,
        readAPIKey: @escaping () -> String? = { APIKeyStore.read() },
        writeAPIKey: @escaping (String) -> Bool = { APIKeyStore.save($0) },
        readOllamaAPIKey: @escaping () -> String? = { APIKeyStore.read(account: APIKeyStore.ollamaAccount) },
        writeOllamaAPIKey: @escaping (String) -> Bool = { APIKeyStore.save($0, account: APIKeyStore.ollamaAccount) }
    ) {
        self.defaults = defaults
        self.loginItem = loginItem
        self.readAPIKey = readAPIKey
        self.readOllamaAPIKey = readOllamaAPIKey
        self.writeAPIKey = writeAPIKey
        self.writeOllamaAPIKey = writeOllamaAPIKey
        self.modelName = defaults.string(forKey: Key.model) ?? EmbeddedModelCatalog.recommended.id
        self.provider = defaults.string(forKey: Key.provider)
            .flatMap(LLMProvider.init(rawValue:)) ?? .local
        self.cloudModel = defaults.string(forKey: Key.cloudModel) ?? CloudModelCatalog.default.id
        self.ollamaCloudModel = defaults.string(forKey: Key.ollamaCloudModel) ?? OllamaCloudCatalog.defaultModel
        self.apiKey = ""
        self.ollamaAPIKey = ""
        let primary = defaults.string(forKey: Key.primaryLanguage)
            .flatMap(PrimaryLanguage.init(rawValue:))
            ?? (defaults.object(forKey: Key.hasCompletedOnboarding) != nil
                ? .polish
                : (systemLanguages.first?.hasPrefix("pl") == true ? .polish : .english))
        defaults.set(primary.rawValue, forKey: Key.primaryLanguage)
        self.primaryLanguage = primary
        let storedSecond = defaults.string(forKey: Key.secondLanguage)
        let second: SecondLanguage? = storedSecond == Self.autoSecond
            ? nil
            : storedSecond.flatMap(SecondLanguage.init(rawValue:)) ?? primary.counterpart.asSecond
        self.secondLanguage = second == primary.asSecond ? primary.counterpart.asSecond : second
        self.formality = defaults.string(forKey: Key.formality)
            .flatMap(Formality.init(rawValue:)) ?? .automatic
        self.fixChord = defaults.data(forKey: Key.fixChord)
            .flatMap { try? JSONDecoder().decode(KeyChord.self, from: $0) } ?? .fixGrammarDefault
        self.translateInPlaceChord = defaults.data(forKey: Key.translateInPlaceChord)
            .flatMap { try? JSONDecoder().decode(KeyChord.self, from: $0) } ?? .translateInPlaceDefault
        self.hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        self.lastNotifiedVersion = defaults.string(forKey: Key.lastNotifiedVersion) ?? ""
        self.launchAtLogin = loginItem.isEnabled
    }

    func refreshLaunchAtLogin() {
        let actual = loginItem.isEnabled
        if launchAtLogin != actual { launchAtLogin = actual }
    }
}
