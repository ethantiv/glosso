import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Glosso

private struct StubLister: ModelListing {
    func availableModels() async throws -> [String] { EmbeddedModelCatalog.models.map(\.id) }
}

private struct StubEngine: EngineProviding {
    func activeBaseURL() async throws -> URL { URL(string: "http://localhost:11434")! }
    func ensureEngine(progress: @escaping @Sendable (Double) -> Void) async throws {}
    func status() async -> EngineStatus { .ready }
}

private struct StubModelManager: ModelManaging {
    func pull(_ model: String) -> AsyncThrowingStream<PullProgress, Error> { .init { $0.finish() } }
    func delete(_ model: String) async throws {}
}

/// The window sizes itself from `formContentHeight`, so a probe that stops finding the scroll view, or a section that
/// pushes the form past the screen, would silently bring back the scrolling this replaced.
@MainActor
@Suite("Settings layout")
struct SettingsLayoutTests {
    // A 13-inch MacBook's visible height is ~930pt; below 800 leaves room for the title bar and a margin.
    private let ceiling: CGFloat = 800

    @Test("every engine's form fits one screen without scrolling")
    func formFitsOnOneScreen() {
        for provider in LLMProvider.allCases {
            // No-op key readers: the cloud sections' SecureFields read the Keychain on appear, which on a re-signed
            // build pops the login-password dialog and stalls the run. The measured layout is the same either way.
            let store = SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                      systemLanguages: ["pl-PL"],
                                      readAPIKey: { nil },
                                      readOllamaAPIKey: { nil })
            store.provider = provider
            let host = NSHostingView(rootView: SettingsView(
                store: store,
                lister: StubLister(),
                cloudLister: StubLister(),
                engine: StubEngine(),
                modelManager: StubModelManager(),
                limiter: GeminiRateLimiter(store: DefaultsRef(UserDefaults(suiteName: UUID().uuidString)!))
            ))
            // In a window, or SwiftUI never lays the scroll content out and the document view measures zero.
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 2000),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = host
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()

            let height = SettingsWindowSizing.formContentHeight(in: host)
            #expect(height != nil, "\(provider): no scroll view found — the probe needs updating")
            #expect((height ?? 0) > 0, "\(provider) measures zero")
            #expect((height ?? 0) <= ceiling, "\(provider) measures \(height ?? 0), over the \(ceiling) ceiling")
        }
    }
}
