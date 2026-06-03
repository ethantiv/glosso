# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS menu-bar agent (`LSUIElement`, no Dock icon) that translates the current selection on **double Cmd+C** using a local LLM (Gemma via Ollama on `localhost:11434`) and streams the result into a floating panel near the cursor. Two empirical decisions are load-bearing and must not be changed lightly: `think:false` is mandatory (Gemma 4 otherwise burns 10–26s on reasoning tokens for an identical translation), and the native REST `/api/generate` is used over the OpenAI-compatible `/v1` layer (which doesn't expose `keep_alive`).

## Build & test

The Xcode project is **generated** by XcodeGen and is git-ignored. Never edit `*.xcodeproj` by hand — change `project.yml`, then regenerate. All four scripts regenerate the project first, so new source files are picked up automatically.

```bash
scripts/gen.sh      # regenerate Glosso.xcodeproj from project.yml
scripts/build.sh    # xcodegen generate + xcodebuild (Debug, arm64) → .build/dd/...
scripts/run.sh      # build + open the app (look for the bubble icon in the menu bar)
scripts/test.sh     # xcodebuild test → .build/TestResults.xcresult
scripts/package.sh  # Release build + signature-preserving zip → .build/release/Glosso.zip
```

`scripts/package.sh` produces a standalone `.zip` for a personal install: unzip, drag `Glosso.app` to `/Applications` (it then shows in Launchpad/Spotlight and runs without Xcode). It uses `ditto` (not `zip`) so the signature survives. Signed with the same free personal team — fine for your own Mac, **not notarized**, so distributing it to other machines would trip Gatekeeper. The "Launch at login" toggle (`SMAppService.mainApp`) only registers reliably once the app lives in `/Applications`.

**Builds and `xcodebuild` must run outside the sandbox** (`dangerouslyDisableSandbox: true`). Inside the sandbox they fail with `Operation not permitted`. `gh` and other network calls (GitHub API, Ollama over TLS) also need `dangerouslyDisableSandbox: true` — in the sandbox they fail with a TLS cert error (`OSStatus -26276`), not the build's `Operation not permitted`. During `/babysit-pr`, resolving a `claude-review` thread (`gh api graphql … resolveReviewThread`) is user-authorized in two cases: (1) findings actually fixed in committed code, and (2) findings you deliberately skipped after posting a rationale reply on the thread (low-value, or whose only fix would change a documented design decision). Leave a thread **unresolved only** when it is genuinely handed to a human — an un-adjudicable product/design call you did not decide yourself. The Bash tool's shell is **zsh** — unquoted `$var` is not word-split; iterate lists with `while IFS= read -r` (a `for x in $list` runs once on the whole string).

Signing uses a **free personal team** (Team ID `F266Z8F83B` in `project.yml`). The scripts pass `-allowProvisioningUpdates` so the first build creates the "Apple Development" cert. Accessibility consent (TCC) is pinned to the signing identity, so changing `DEVELOPMENT_TEAM`/signing style means re-granting it (`tccutil reset Accessibility com.mirek.glosso`, then re-add the app).

Live "Cannot find type X" / "No such module 'Testing'" diagnostics in the editor before a build are **SourceKit noise** (single module, not yet indexed), not real errors — verify against an actual `scripts/build.sh`/`test.sh` run.

Tests use the **Swift Testing** framework (`import Testing`, `@Test`, `@Suite`, `#expect`) — not XCTest. To run one suite or test, add `-only-testing`:

```bash
xcodebuild test -project Glosso.xcodeproj -scheme Glosso \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/dd \
  -only-testing:GlossoTests/AppCoordinatorTests
```

## Architecture

**`Sources/Core/Contracts.swift` is the frozen seam.** Every module talks to the others only through the protocols and value types defined there (`LLMClient`, `HotkeyMonitor`, `PasteboardReading`, `TranslationPopupPresenting`, `AccessibilityAuthorizing`, `DoubleKeyDetecting`, `TimeSource`, `ModelListing`, plus the `TranslationEvent`/`TranslationError`/`CaptureError`/`SecondLanguage`/`Formality` enums and `LLMConfig`). `LLMClient.translate(_:model:second:formality:)` and `prewarm(model:)` take the user-selected model and second language per call; `alternatives(for:in:source:second:model:)` (non-streaming, returns `[String]`) and `reword(original:to:in:source:second:formality:model:)` (streaming, like `translate`) back the per-word alternatives feature (issue #17). Concrete types are injected; tests swap in fakes from `Tests/Support/`. When changing a cross-module behavior, change the protocol here first.

`AppCoordinator` (`Sources/Coordinator/`, `@MainActor`) wires the modules and owns the flow. `AppDelegate` (`Sources/App/GlossoApp.swift`) builds the real instances and starts it; it **early-returns under XCTest** (`XCTestConfigurationFilePath`) so the app side effects don't fire during tests.

The four functional modules, each behind a protocol:

- **Hotkey** (`Sources/Hotkey/`) — `GlobalHotkeyMonitor` is a *passive* `NSEvent.addGlobalMonitorForEvents(.keyDown)` watcher (keyCode 8 = "c" + Command). Both Cmd+C presses still copy normally. `DoubleCopyDetector` decides "double" by measuring the gap (~0.3s window) and resets after a hit so a third rapid press can't pair with the second. This is why the only OS permission needed is **Accessibility**, not a registered hotkey.
- **Capture** (`Sources/Capture/`) — reads `NSPasteboard`. `SelectionGuard` enforces that `changeCount` rose above a baseline (proof the user actually copied) and that the text is non-empty. When the poll loop times out (the app never copied on Cmd+C — Safari/WebKit does this inconsistently), `AppCoordinator` falls back to `AXSelectionReader` (`AXSelectionReading`), which reads the focused element's `AXSelectedText` directly via the Accessibility API — no pasteboard, no new permission (the AX consent the hotkey monitor already needs covers it). Because that read resolves whatever is focused *at fallback time* (~480ms after the press), `AppCoordinator` snapshots the frontmost app's PID at the double-press and bails out of the AX fallback if it changed (a Cmd+Tab mid-poll), so it never translates another app's selection. Deeper fallbacks (AppleScript, synthesized Cmd+C, Safari-via-JavaScript) stay deferred.
- **LLM** (`Sources/LLM/`) — `OllamaClient` POSTs to `/api/generate` with `stream:true`, parses the NDJSON line stream (`NDJSONStreamParser`), and yields `.token`/`.finished` through an `AsyncThrowingStream`. `PromptBuilder` carries the **PL↔(selected second language) swap logic inside the prompt itself** (`build`), plus the per-word `buildAlternatives` (one-per-line list, parsed by `AlternativesParser`) and `buildReword` (constrained re-translation) prompts for issue #17. `prewarm(model:)` is best-effort (failures are swallowed) and keeps the model resident via `keep_alive`.
- **Popup** (`Sources/Popup/`) — `TranslationPopupController` shows a borderless non-activating `FloatingPanel` that never becomes key (won't steal focus). Esc dismisses it (via the CGEventTap below) and the title-bar close button closes it; a click *outside* the window closes only an open alternatives dropdown (issue #30), never the panel — that outside-click-to-dismiss-the-panel was deliberately dropped in `5f4a549` once the window became movable with a close button. The panel sizes to its SwiftUI content via `NSHostingController.sizingOptions = .preferredContentSize` (without it the panel keeps its initial frame and truncates long text). AppKit pins the bottom-left origin on resize, so a `didResizeNotification` observer re-pins the saved top-left to make it grow downward, not up over the cursor; the text view caps height at 400pt and scrolls. In the `.done` phase the result becomes a `FlowLayout` of individually clickable words (`WordFlow.swift`: `Tokenizer`, `FlowLayout`, `AlternativesDropdown`); clicking one opens an alternatives dropdown rendered as an **in-window SwiftUI overlay** (`overlayPreferenceValue` anchored to the word) — deliberately **not** an `NSPopover`/`Menu`, which would force the panel to become key and break the non-activating focus model. Esc is layered: it closes an open dropdown first, then dismisses the panel. This trades away drag-to-select on the result (the header Copy button still copies the whole translation).

A fifth **Settings** module (`Sources/Settings/`) holds the user-editable config: `SettingsStore` (`@Observable`, UserDefaults-backed) persists the Ollama `model` and the `secondLanguage` (the non-Polish side of the pair; English default). `SettingsView` is a SwiftUI `Settings` scene opened via `SettingsLink` in the menu; its model picker is populated live from `OllamaModelLister` (`ModelListing`, `GET /api/tags`, derived from the generate endpoint's host). A "Launch at login" toggle binds to `SettingsStore.launchAtLogin`, which is **not** UserDefaults-backed: it derives from and drives `SMAppService.mainApp` through `LoginItemManaging` (`SMAppServiceLoginItem`), so the actual system registration is the source of truth (a user revoking it in System Settings is reflected on `refreshLaunchAtLogin`, called when the window appears). The empirical invariants (`think:false`, `temperature:0`, `keep_alive`, `endpoint`) stay locked in `OllamaClient`'s base config and are **not** exposed in the UI.

### Two subtleties that aren't obvious from a single file

1. **The capture poll loop** (`AppCoordinator.captureAndTranslate`): the second Cmd+C only *triggers* the copy, so at the instant the double-press is detected the new clipboard contents aren't there yet. The monitor samples the baseline `changeCount` at the *first* Cmd+C (`registerPress`) — so it precedes the second copy even for apps that copy synchronously on keyDown (Chromium/Electron, Java) — and hands it to the coordinator via `onDoubleCopy`, which polls `readSelection` until `changeCount` rises (default 12ms × 40 attempts ≈ 480ms, to tolerate slow apps' copies) before streaming.

2. **`DirectionDetector` is UI-only.** `detect(_:second:)` uses `NLLanguageRecognizer` (constrained to Polish + the selected second language) purely to pick the arrow label (PL→XX / XX→PL). The *actual* translation direction is decided by the model from the prompt's swap instruction. The two must stay mirrored: Polish input → the selected second language, everything else → Polish.

### Config & permissions

`LLMConfig.default` (model `gemma4:26b-mlx`, `think:false`, `temperature:0`, `keepAlive:"30m"`) lives in `Contracts.swift` and seeds the fresh-install defaults. At runtime the `model` and the second language come from `SettingsStore` (UserDefaults) per translation; `think`/`temperature`/`keepAlive`/`endpoint` stay fixed in `OllamaClient`'s base config. The app is **not sandboxed** (`Generated/Glosso.entitlements` sets `app-sandbox: false`, `network.client: true`) because Accessibility is incompatible with MAS sandboxing. Deployment target is macOS 26.0, Swift 6 (strict concurrency — note the `MainActor.assumeIsolated` shims around non-isolated AppKit monitor callbacks).

App icon and the custom menu-bar glyph live in `Sources/Assets.xcassets/` (`AppIcon.appiconset`, `MenuBarIcon.imageset`); the icon name is wired via `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` in `project.yml`.

## Tests

- `Tests/` — fast unit tests, no network, using the fakes in `Tests/Support/`.
- `TestsIntegration/OllamaLiveTests.swift` — hits a real Ollama and **silently skips (returns early) when `localhost:11434` is unreachable**, so the suite stays green without a running daemon.
- Every test/helper file needs `@testable import Glosso` to see our types, and `import Foundation` when it uses Foundation types (e.g. `TimeInterval`). Helpers under `Tests/Support/` are easy to forget.
