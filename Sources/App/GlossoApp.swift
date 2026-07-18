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
            // While an update waits, swap in a glyph variant with a download arrow
            // baked into the same template artwork — a SwiftUI overlay can't keep a
            // distinct colour through the menu bar's monochrome tint, and the menu
            // bar adapts this template image to light/dark on its own.
            Image(appDelegate.appState.updateAvailable != nil ? "MenuBarIconUpdate" : "MenuBarIcon")
                .accessibilityLabel("Glosso")
        }

        Settings {
            SettingsView(
                store: appDelegate.settings,
                lister: appDelegate.modelLister,
                engine: appDelegate.engine,
                modelManager: appDelegate.modelManager
            )
        }
    }
}

// Replaces `SettingsLink`, which on an `LSUIElement` agent opens the window in
// the background and on the launch Space. Reading `openSettings` inside a view
// (not the `App`) guarantees the environment action resolves; activating the app
// after opening brings the window to the front and — together with the window's
// `.moveToActiveSpace` collection behavior — onto the currently active Space.
private struct OpenSettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(loc("Ustawienia…", "Settings…")) {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// Quick language switching without opening Settings: two pickers, which the
// MenuBarExtra's default menu style renders as submenus with checkmarks. The
// second-language list mirrors SettingsView: an Automatic entry plus every
// language except the primary (the pair is never X↔X).
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
    let appState = AppState()
    let settings = SettingsStore()
    // Shared with EngineManager so a spawned `ollama serve` can be killed
    // synchronously on quit (applicationWillTerminate can't await the actor).
    let engineBox = EngineProcessBox()
    lazy var engine = EngineManager(box: engineBox)
    lazy var modelLister: OllamaModelLister = OllamaModelLister(endpointProvider: Self.endpointProvider(engine))
    lazy var modelManager: OllamaModelManager = OllamaModelManager(endpointProvider: Self.endpointProvider(engine))

    // Builds the `@Sendable` endpoint resolver off the MainActor so its closure
    // isn't inferred as main-actor-isolated (which can't also be Sendable).
    nonisolated static func endpointProvider(_ engine: EngineManager) -> @Sendable () async throws -> URL {
        { try await engine.activeBaseURL() }
    }
    // Injectable so tests can drive the granted↔revoked transitions in
    // recheckAccessibility() with a fake; production keeps the real AXChecker.
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
        let llm = OllamaClient(endpointProvider: Self.endpointProvider(engine))
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

        // Best-effort, silent: surfaces a "download" item + badge when a newer
        // release exists, and fires one notification per new version (the menu line
        // alone is easy to miss). Any failure leaves updateAvailable nil (no noise).
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

        // Accessibility can be revoked while we run; re-check whenever an app
        // activates so the menu stops claiming "Nasłuch aktywny" when it isn't.
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

    // The standard panel pulls icon/name/version from the bundle; only the author
    // line and the two links are supplied via .credits. Activating is needed for an
    // LSUIElement agent — the panel otherwise opens behind, like the Settings window.
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

    /// Fetches the pending release `.zip` into ~/Downloads. Shared by the menu item
    /// and the notification tap; a no-op if no update is currently known.
    func downloadUpdate() {
        guard let asset = appState.updateAvailable?.asset else { return }
        Task { await UpdateDownloader.download(asset) }
    }

    // Tapping the update notification downloads straight away (the menu item's job),
    // so the user never has to hunt for the menu-bar icon afterwards.
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
