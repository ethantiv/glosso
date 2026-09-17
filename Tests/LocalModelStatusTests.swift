import AppKit
import Foundation
import Testing
@testable import Glosso

@Suite struct LocalModelStatusTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func matchesTheActiveModelByName() {
        let loaded = [LoadedModel(name: "llama3:8b", expiresAt: nil), LoadedModel(name: "gemma4:26b-mlx", expiresAt: now)]
        #expect(LocalModelStatus.from(loaded: loaded, model: "gemma4:26b-mlx") == .loaded(expiresAt: now))
        #expect(LocalModelStatus.from(loaded: loaded, model: "gemma4:31b") == .idle)
        #expect(LocalModelStatus.from(loaded: [], model: "gemma4:26b-mlx") == .idle)
    }

    @Test func labelsRoundMinutesUpAndTreatFarDatesAsNever() {
        L10n.$override.withValue(.polish) {
            #expect(LocalModelStatus.idle.label(now: now) == "Model lokalny: uśpiony")
            #expect(LocalModelStatus.loaded(expiresAt: now.addingTimeInterval(41 * 60 + 1)).label(now: now)
                    == "Model lokalny: załadowany · zwolni za 42 min")
            #expect(LocalModelStatus.loaded(expiresAt: now.addingTimeInterval(10 * 365 * 86_400)).label(now: now)
                    == "Model lokalny: załadowany · nie zwalnia")
            #expect(LocalModelStatus.loaded(expiresAt: nil).label(now: now)
                    == "Model lokalny: załadowany · nie zwalnia")
        }
    }

    @MainActor @Test func glyphKeepsTheBaseSizeAndTemplateFlag() {
        let base = NSImage(named: "MenuBarIcon")!.size
        for model in [LocalModelStatus?.none, .idle, .loaded(expiresAt: nil)] {
            for update in [false, true] {
                let image = MenuBarGlyph.image(update: update, model: model)
                #expect(image.isTemplate == (model == nil))
                #expect(image.size == (update ? NSImage(named: "MenuBarIconUpdate")!.size : base))
            }
        }
    }

    @Test func parsesOllamaExpiryWithMicrosecondsAndOffset() {
        let date = OllamaModelLister.parseDate("2026-09-17T14:38:31.83753+02:00")
        #expect(date == ISO8601DateFormatter().date(from: "2026-09-17T12:38:31Z"))
    }
}
