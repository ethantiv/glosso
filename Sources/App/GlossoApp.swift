import SwiftUI
import AppKit
import UserNotifications

@main
struct GlossoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            if appDelegate.appState.listening {
                Text(loc("Glosso · aktywny", "Glosso · active"))
            } else if appDelegate.appState.accessibilityGranted {
                Text(loc("Dostępność OK, ale nasłuch nie wystartował.",
                         "Accessibility OK, but the listener didn't start."))
                Button(loc("Sprawdź ponownie", "Check again")) {
                    appDelegate.recheckAccessibility()
                }
            } else {
                Text(loc("Brak uprawnienia Dostępność (Accessibility)",
                         "Missing the Accessibility permission"))
                Button(loc("Otwórz Ustawienia → Prywatność → Dostępność",
                           "Open Settings → Privacy → Accessibility")) {
                    appDelegate.openAccessibilitySettings()
                }
                Button(loc("Sprawdź ponownie", "Check again")) {
                    appDelegate.recheckAccessibility()
                }
            }
            Divider()
            LanguageMenus(store: appDelegate.settings)
            Divider()
            if let update = appDelegate.appState.updateAvailable {
                Button(loc("Dostępna nowa wersja \(update.version) — Pobierz do Downloads",
                           "New version \(update.version) available — Download to Downloads")) {
                    appDelegate.downloadUpdate()
                }
            }
            OpenSettingsButton()
            Button(loc("O aplikacji…", "About…")) { appDelegate.showAbout() }
            Button(loc("Zakończ", "Quit")) { NSApplication.shared.terminate(nil) }
        } label: {
            Image(appDelegate.appState.updateAvailable != nil ? "MenuBarIconUpdate" : "MenuBarIcon")
                .accessibilityLabel("Glosso")
        }

        Settings {
            SettingsView(
                store: appDelegate.settings,
                lister: appDelegate.modelLister,
                engine: appDelegate.engine,
                modelManager: appDelegate.modelManager,
                limiter: appDelegate.cloudLimiter
            )
        }
    }
}

private struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(loc("Ustawienia…", "Settings…")) {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct LanguageMenus: View {
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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    nonisolated static let updateNotificationID = "glosso.update"
    /// One banner per outage, not one per call: a single capture prefetches every verb.
    nonisolated static let fallbackNotificationID = "glosso.fallback"
    let appState = AppState()
    let settings = SettingsStore()
    /// Shared so the Settings quota line counts the same requests the client books.
    let cloudLimiter = GeminiRateLimiter()
    let engineBox = EngineProcessBox()
    lazy var engine = EngineManager(box: engineBox)
    lazy var modelLister: OllamaModelLister = OllamaModelLister(endpointProvider: Self.endpointProvider(engine))
    lazy var modelManager: OllamaModelManager = OllamaModelManager(endpointProvider: Self.endpointProvider(engine))

    nonisolated static func endpointProvider(_ engine: EngineManager) -> @Sendable () async throws -> URL {
        { try await engine.activeBaseURL() }
    }
    var ax: any AccessibilityAuthorizing = AXChecker()
    var coordinator: AppCoordinator?
    private var activationObserver: NSObjectProtocol?
    lazy var onboarding = OnboardingController(
        store: settings,
        lister: modelLister,
        engine: engine,
        modelManager: modelManager,
        appState: appState,
        onOpenAccessibility: { [weak self] in self?.openAccessibilitySettings() },
        onRecheckAccessibility: { [weak self] in self?.recheckAccessibility() }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        appState.accessibilityGranted = ax.isTrusted
        if !ax.isTrusted {
            ax.requestAccess(prompt: true)
        }

        let reader = SystemPasteboardReader()
        let llm = RoutingLLMClient(
            local: OllamaClient(endpointProvider: Self.endpointProvider(engine)),
            cloud: GeminiClient(limiter: cloudLimiter),
            provider: { [settings] in await MainActor.run { settings.provider } },
            localModel: { [settings] in await MainActor.run { settings.modelName } },
            onFallback: { error in
                Task { @MainActor in
                    SystemUserNotifier.post(
                        error.userMessage + " " + loc("Przełączam na model lokalny.",
                                                      "Switching to the local model."),
                        identifier: Self.fallbackNotificationID
                    )
                }
            }
        )
        let coordinator = AppCoordinator(
            llm: llm,
            monitor: GlobalHotkeyMonitor(
                changeCountProvider: { reader.currentChangeCount },
                chordProvider: { [settings] in (settings.fixChord, settings.translateInPlaceChord) }
            ),
            reader: reader,
            axReader: AXSelectionReader(),
            popup: TranslationPopupController(),
            settings: settings,
            articleReader: ReaderController(llm: llm, settings: settings)
        )
        appState.listening = coordinator.start()
        self.coordinator = coordinator

        UNUserNotificationCenter.current().delegate = self
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        Task { [appState, settings] in
            if let update = await GitHubUpdateChecker().availableUpdate(currentVersion: currentVersion) {
                appState.updateAvailable = update
                if update.version != settings.lastNotifiedVersion {
                    settings.lastNotifiedVersion = update.version
                    SystemUserNotifier.post(
                        loc("Dostępna nowa wersja \(update.version) — kliknij, aby pobrać.",
                            "New version \(update.version) available — click to download."),
                        identifier: Self.updateNotificationID
                    )
                }
            }
        }

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheckAccessibility() }
        }

        if !settings.hasCompletedOnboarding {
            onboarding.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        engineBox.terminate()
    }

    func openAccessibilitySettings() {
        ax.openSystemSettings()
    }

    func showAbout() {
        let center = NSMutableParagraphStyle()
        center.alignment = .center
        let credits = NSMutableAttributedString(
            string: loc("Autor: Mirosław Zaniewicz\n\n", "Author: Mirosław Zaniewicz\n\n"),
            attributes: [.foregroundColor: NSColor.labelColor, .paragraphStyle: center]
        )
        func link(_ label: String, _ url: String) {
            credits.append(NSAttributedString(
                string: label + "\n",
                attributes: [.link: URL(string: url)!, .paragraphStyle: center]
            ))
        }
        link(loc("Repozytorium", "Repository"), "https://github.com/ethantiv/glosso")
        link(loc("Strona projektu", "Project website"), "https://ethantiv.github.io/glosso/")

        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }

    func downloadUpdate() {
        guard let asset = appState.updateAvailable?.asset else { return }
        Task { await UpdateDownloader.download(asset) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isUpdate = response.notification.request.identifier == Self.updateNotificationID
        completionHandler()
        guard isUpdate else { return }
        Task { @MainActor in self.downloadUpdate() }
    }

    func recheckAccessibility() {
        appState.accessibilityGranted = ax.isTrusted
        if ax.isTrusted {
            if appState.listening == false {
                appState.listening = coordinator?.start() ?? false
            }
        } else if appState.listening {
            coordinator?.stop()
            appState.listening = false
        }
    }
}
