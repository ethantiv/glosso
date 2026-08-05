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
            Button(appDelegate.appState.checkingForUpdates
                   ? loc("Sprawdzam aktualizacje…", "Checking for updates…")
                   : loc("Sprawdź aktualizacje…", "Check for Updates…")) {
                appDelegate.checkForUpdates(announce: true)
            }
            .disabled(appDelegate.appState.checkingForUpdates)
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
                cloudLister: appDelegate.ollamaCloudLister,
                engine: appDelegate.engine,
                modelManager: appDelegate.modelManager,
                limiter: appDelegate.cloudLimiter
            )
        }
        .defaultSize(width: 520, height: 620)
        // .contentMinSize, not .contentSize: the window grows as far as the user wants, it just can't shrink below the form.
        .windowResizability(.contentMinSize)
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
    lazy var cloudLimiter = GeminiRateLimiter(onWait: { [weak self] seconds in
        Task { @MainActor in self?.articleReader?.cloudWait(seconds) }
    })
    private var articleReader: ReaderController?
    let engineBox = EngineProcessBox()
    lazy var engine = EngineManager(box: engineBox)
    lazy var modelLister: OllamaModelLister = OllamaModelLister(endpointProvider: Self.endpointProvider(engine))
    lazy var modelManager: OllamaModelManager = OllamaModelManager(endpointProvider: Self.endpointProvider(engine))
    /// The cloud's own /api/tags answers unauthenticated, so the model list needs no key and stays current as Ollama retires models.
    let ollamaCloudLister = OllamaModelLister(endpointProvider: { OllamaCloudCatalog.baseURL })

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
            // The same client, only pointed at Ollama's host and signed — no limiter, because the cloud meters GPU time, not requests.
            ollamaCloud: OllamaClient(
                endpointProvider: { OllamaCloudCatalog.baseURL },
                keyProvider: { APIKeyStore.read(account: APIKeyStore.ollamaAccount) }
            ),
            provider: { [settings] in await MainActor.run { settings.provider } },
            localModel: { [settings] in await MainActor.run { settings.modelName } },
            onFallback: { [weak self] error, longForm in
                Task { @MainActor in
                    // Only the reader's own long-form calls may relabel its footer; a popup capture's hand-over says
                    // nothing about the engine still translating the article.
                    if longForm { self?.articleReader?.engineFallback() }
                    SystemUserNotifier.post(
                        error.userMessage + " " + loc("Przełączam na model lokalny.",
                                                      "Switching to the local model."),
                        identifier: Self.fallbackNotificationID
                    )
                }
            },
            // Cloud-only installs never download an engine, so there is nothing for the deadline to hand over to. Anything short of `.needsDownload` is enough, since the local path provisions on demand — the same bar the error-driven fallbacks already clear. `status`, not `activeBaseURL`: the latter provisions here and now, spawning `ollama serve` and waiting up to ~2min inside an uncancellable task, which would outlast the very deadline it gates.
            localReady: { [engine] in await engine.status() != .needsDownload }
        )
        let articleReader = ReaderController(llm: llm, settings: settings)
        self.articleReader = articleReader
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
            articleReader: articleReader
        )
        appState.listening = coordinator.start()
        self.coordinator = coordinator

        UNUserNotificationCenter.current().delegate = self
        checkForUpdates(announce: false)

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

    nonisolated static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// `announce` is the manual path: the menu closes on click, so the only visible answer is a modal.
    ///
    /// Only that path raises the flag. A double alert is the thing worth guarding, and the launch check is silent —
    /// sharing the flag with it would grey the menu item out for the whole of URLSession's 60s timeout behind a
    /// captive portal, exactly when the user reaches for it.
    func checkForUpdates(announce: Bool) {
        guard !(announce && appState.checkingForUpdates) else { return }
        if announce { appState.checkingForUpdates = true }
        let current = Self.currentVersion
        Task { [appState, settings] in
            do {
                let update = try await GitHubUpdateChecker().check(currentVersion: current)
                if announce { appState.checkingForUpdates = false }
                appState.updateAvailable = update
                if let update, update.version != settings.lastNotifiedVersion {
                    settings.lastNotifiedVersion = update.version
                    SystemUserNotifier.post(
                        loc("Dostępna nowa wersja \(update.version) — kliknij, aby pobrać.",
                            "New version \(update.version) available — click to download."),
                        identifier: Self.updateNotificationID
                    )
                }
                if announce { showUpdateAlert(update: update, failed: false, current: current) }
            } catch {
                // A failed check leaves `updateAvailable` alone: it must not retract a version the launch check found.
                if announce {
                    appState.checkingForUpdates = false
                    showUpdateAlert(update: nil, failed: true, current: current)
                }
            }
        }
    }

    private func showUpdateAlert(update: (version: String, asset: URL)?, failed: Bool, current: String) {
        let alert = NSAlert()
        if failed {
            alert.messageText = loc("Nie udało się sprawdzić aktualizacji",
                                    "Couldn't check for updates")
            alert.informativeText = loc("Sprawdź połączenie z internetem i spróbuj ponownie.",
                                        "Check your internet connection and try again.")
        } else if let update {
            alert.messageText = loc("Dostępna nowa wersja \(update.version)",
                                    "New version \(update.version) available")
            alert.informativeText = loc("Masz \(current). Pobrać nową wersję do folderu Pobrane?",
                                        "You have \(current). Download the new version to Downloads?")
            alert.addButton(withTitle: loc("Pobierz", "Download"))
            // AppKit maps Escape only onto a button titled "Cancel", so a custom title has to claim it by hand.
            alert.addButton(withTitle: loc("Nie teraz", "Not now")).keyEquivalent = "\u{1b}"
        } else {
            alert.messageText = loc("Masz najnowszą wersję", "You're up to date")
            alert.informativeText = loc("Glosso \(current) jest aktualna.",
                                        "Glosso \(current) is the latest version.")
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, update != nil { downloadUpdate() }
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
