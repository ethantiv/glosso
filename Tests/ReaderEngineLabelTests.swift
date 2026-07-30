import Testing
@testable import Glosso

@Suite struct ReaderEngineLabelTests {
    // The footer answers "who is translating this?", so the label must carry the model id the request was built
    // with — the friendly catalog names are speed tiers ("Zrównoważony"), which don't identify a model.
    @Test func labelCarriesProviderAndModelID() {
        #expect(ReaderController.engineLabel(provider: .local, model: "gemma4:26b-mlx")
                    .contains("gemma4:26b-mlx"))
        #expect(ReaderController.engineLabel(provider: .cloud, model: "gemma-4-31b-it")
                    .contains("gemma-4-31b-it"))
        #expect(ReaderController.engineLabel(provider: .ollamaCloud, model: "gemma4:31b")
                    .contains("gemma4:31b"))
    }

    // Local and the two clouds must be told apart at a glance: that is the whole point of the line.
    @Test func labelDistinguishesTheThreeProviders() {
        let labels = LLMProvider.allCases.map { ReaderController.engineLabel(provider: $0, model: "m") }
        #expect(Set(labels).count == LLMProvider.allCases.count)
        for (provider, label) in zip(LLMProvider.allCases, labels) {
            #expect(label.hasPrefix(provider.displayName))
        }
    }
}
