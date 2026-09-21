import Foundation
import Testing
import WebKit
@testable import Glosso

private actor ContextBackend: GenerationBackend {
    private(set) var models: [String] = []
    private(set) var prompts: [String] = []
    let onFirst: @Sendable () async -> Void
    init(onFirst: @escaping @Sendable () async -> Void = {}) { self.onFirst = onFirst }
    func generate(prompt: String, model: String, timeout: TimeInterval?, numPredict: Int?) async throws -> String {
        models.append(model); prompts.append(prompt)
        if models.count == 1 { await onFirst() }
        return "<p>Przetłumaczona treść.</p>"
    }
    nonisolated func streamGeneration(prompt: String, model: String) -> AsyncThrowingStream<TranslationEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func prewarm(model: String) async throws {}
}

@MainActor
private struct StaticArticle: ArticleExtracting {
    func extract(from url: URL) async throws -> ArticleExtractor.ExtractedArticle {
        .init(title: "A long journey through the countryside", byline: nil,
              content: "<p>The first day of our journey began early in the morning.</p><p>We watched the sun rise above the mountains and continued on our way.</p>")
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1))) struct ReaderRunContextTests {
    @Test func changingSettingsMidArticleCannotChangeRoutingOrCacheLanguage() async throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.primaryLanguage = .polish
        settings.provider = .cloud
        let model = settings.activeModel
        let cloud = ContextBackend {
            await MainActor.run { settings.primaryLanguage = .english; settings.provider = .local; settings.modelName = "changed" }
        }
        let local = ContextBackend()
        let routing = RoutingLLMClient(local: local, cloud: cloud, ollamaCloud: local,
            provider: { await MainActor.run { settings.provider } }, localModel: { "local-original" }, onFallback: { _, _ in })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ReaderRepository(cache: ReaderCache(directory: root.appendingPathComponent("cache")),
                                          saved: SavedArticleStore(directory: root.appendingPathComponent("saved")))
        let controller = ReaderController(llm: routing, settings: settings, repository: repository, extractor: StaticArticle())
        let run = controller.makeRun()
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        let url = URL(string: "https://example.com/article")!
        await controller.run(url: url, in: web, run: run)
        let models = await cloud.models
        #expect(models.count >= 3)
        #expect(models.allSatisfy { $0 == model })
        #expect(await local.models.isEmpty)
        let cached = await repository.cached(url, primary: .polish)
        #expect(cached != nil)
        #expect(cached?.engine == "Google AI · \(model)")
        #expect(await repository.cached(url, primary: .english) == nil)
    }
}

@MainActor
private final class DelayedArticle: ArticleExtracting {
    let started = StreamGate()
    var pending: CheckedContinuation<Void, Never>?
    func extract(from url: URL) async throws -> ArticleExtractor.ExtractedArticle {
        if url.lastPathComponent == "old" {
            await withCheckedContinuation { pending = $0; started.release() }
        }
        return .init(title: url.lastPathComponent, byline: nil, content: "<p>" + url.lastPathComponent + "</p>")
    }
}

extension ReaderRunContextTests {
    @Test func cancelledArticleCannotPaintLateResultsIntoTheNextDocument() async throws {
        let directory = TestDirectory()
        let repository = ReaderRepository(cache: ReaderCache(directory: directory.url.appendingPathComponent("cache")),
                                          saved: SavedArticleStore(directory: directory.url.appendingPathComponent("saved")))
        let extractor = DelayedArticle()
        let controller = ReaderController(llm: FakeLLMClient(), settings: SettingsStore(defaults: TestDefaults()),
            repository: repository, extractor: extractor)
        let configuration = WKWebViewConfiguration(); configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: configuration)
        let oldURL = URL(string: "https://example.com/old")!
        let oldRun = controller.makeRun()
        let oldTask = Task { await controller.run(url: oldURL, in: web, run: oldRun) }
        await extractor.started.wait()
        oldTask.cancel()
        let nextURL = URL(string: "https://example.com/next")!
        await controller.run(url: nextURL, in: web, run: controller.makeRun())
        let before = try await web.evaluateReaderString("document.body.innerHTML")
        extractor.pending?.resume()
        await oldTask.value
        #expect(try await web.evaluateReaderString("document.body.innerHTML") == before)
        #expect(await repository.cached(oldURL, primary: oldRun.context.primary) == nil)
        #expect(await repository.list().map(\.url) == [nextURL])
    }
}
