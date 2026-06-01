# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A macOS menu-bar agent (`LSUIElement`, no Dock icon) that translates the current
selection on **double Cmd+C** using a local LLM (Gemma via Ollama on
`localhost:11434`) and streams the result into a floating panel near the cursor.
`IDEA.md` holds the full design rationale and the empirical decisions behind it
(read it before changing behavior — e.g. why `think:false` is mandatory, why the
native REST `/api/generate` is used over the OpenAI-compatible `/v1` layer).

## Build & test

The Xcode project is **generated** by XcodeGen and is git-ignored. Never edit
`*.xcodeproj` by hand — change `project.yml`, then regenerate. All four scripts
regenerate the project first, so new source files are picked up automatically.

```bash
scripts/gen.sh      # regenerate TranslatorMenuBar.xcodeproj from project.yml
scripts/build.sh    # xcodegen generate + xcodebuild (Debug, arm64) → .build/dd/...
scripts/run.sh      # build + open the app (look for the bubble icon in the menu bar)
scripts/test.sh     # xcodebuild test → .build/TestResults.xcresult
```

**Builds and `xcodebuild` must run outside the sandbox** (`dangerouslyDisableSandbox: true`).
Inside the sandbox they fail with `Operation not permitted`.
`gh` and other network calls (GitHub API, Ollama over TLS) also need
`dangerouslyDisableSandbox: true` — in the sandbox they fail with a TLS cert
error (`OSStatus -26276`), not the build's `Operation not permitted`.
During `/babysit-pr`, resolving a `claude-review` thread
(`gh api graphql … resolveReviewThread`) is user-authorized in two cases:
(1) findings actually fixed in committed code, and (2) findings you deliberately
skipped after posting a rationale reply on the thread (low-value, or whose only
fix would change a documented design decision). Leave a thread **unresolved
only** when it is genuinely handed to a human — an un-adjudicable product/design
call you did not decide yourself.
The Bash tool's shell is **zsh** — unquoted `$var` is not word-split; iterate
lists with `while IFS= read -r` (a `for x in $list` runs once on the whole string).

Signing uses a **free personal team** (Team ID `F266Z8F83B` in `project.yml`).
The scripts pass `-allowProvisioningUpdates` so the first build creates the
"Apple Development" cert. Accessibility consent (TCC) is pinned to the signing
identity, so changing `DEVELOPMENT_TEAM`/signing style means re-granting it
(`tccutil reset Accessibility com.mirek.translatormenubar`, then re-add the app).

Live "Cannot find type X" / "No such module 'Testing'" diagnostics in the
editor before a build are **SourceKit noise** (single module, not yet indexed),
not real errors — verify against an actual `scripts/build.sh`/`test.sh` run.

Tests use the **Swift Testing** framework (`import Testing`, `@Test`, `@Suite`,
`#expect`) — not XCTest. To run one suite or test, add `-only-testing`:

```bash
xcodebuild test -project TranslatorMenuBar.xcodeproj -scheme TranslatorMenuBar \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/dd \
  -only-testing:TranslatorMenuBarTests/AppCoordinatorTests
```

## Architecture

**`Sources/Core/Contracts.swift` is the frozen seam.** Every module talks to the
others only through the protocols and value types defined there (`LLMClient`,
`HotkeyMonitor`, `PasteboardReading`, `TranslationPopupPresenting`,
`AccessibilityAuthorizing`, `DoubleKeyDetecting`, `TimeSource`, `ModelListing`,
plus the `TranslationEvent`/`TranslationError`/`CaptureError`/`SecondLanguage`
enums and `LLMConfig`). `LLMClient.translate(_:model:second:)` and
`prewarm(model:)` take the user-selected model and second language per call.
Concrete types are injected; tests swap in fakes from `Tests/Support/`. When
changing a cross-module behavior, change the protocol here first.

`AppCoordinator` (`@MainActor`) wires the modules and owns the flow. `AppDelegate`
(`Sources/App/TranslatorApp.swift`) builds the real instances and starts it; it
**early-returns under XCTest** (`XCTestConfigurationFilePath`) so the app side
effects don't fire during tests.

The four functional modules, each behind a protocol:

- **Hotkey** (`Sources/Hotkey/`) — `GlobalHotkeyMonitor` is a *passive*
  `NSEvent.addGlobalMonitorForEvents(.keyDown)` watcher (keyCode 8 = "c" +
  Command). Both Cmd+C presses still copy normally. `DoubleCopyDetector` decides
  "double" by measuring the gap (~0.3s window) and resets after a hit so a third
  rapid press can't pair with the second. This is why the only OS permission
  needed is **Accessibility**, not a registered hotkey.
- **Capture** (`Sources/Capture/`) — reads `NSPasteboard`. `SelectionGuard`
  enforces that `changeCount` rose above a baseline (proof the user actually
  copied) and that the text is non-empty. When the poll loop times out (the app
  never copied on Cmd+C — Safari/WebKit does this inconsistently),
  `AppCoordinator` falls back to `AXSelectionReader` (`AXSelectionReading`),
  which reads the focused element's `AXSelectedText` directly via the
  Accessibility API — no pasteboard, no new permission (the AX consent the
  hotkey monitor already needs covers it). Deeper fallbacks (AppleScript,
  synthesized Cmd+C, Safari-via-JavaScript) stay deferred.
- **LLM** (`Sources/LLM/`) — `OllamaClient` POSTs to `/api/generate` with
  `stream:true`, parses the NDJSON line stream (`NDJSONStreamParser`), and yields
  `.token`/`.finished` through an `AsyncThrowingStream`. `PromptBuilder` carries
  the **PL↔(selected second language) swap logic inside the prompt itself**.
  `prewarm(model:)` is best-effort (failures are swallowed) and keeps the model
  resident via `keep_alive`.
- **Popup** (`Sources/Popup/`) — `TranslationPopupController` shows a borderless
  non-activating `FloatingPanel` that never becomes key (won't steal focus).
  Esc (local monitor) and any click outside (global monitor) dismiss it.
  The panel sizes to its SwiftUI content via
  `NSHostingController.sizingOptions = .preferredContentSize` (without it the
  panel keeps its initial frame and truncates long text). AppKit pins the
  bottom-left origin on resize, so a `didResizeNotification` observer re-pins
  the saved top-left to make it grow downward, not up over the cursor; the
  text view caps height at 400pt and scrolls.

A fifth **Settings** module (`Sources/Settings/`) holds the user-editable config:
`SettingsStore` (`@Observable`, UserDefaults-backed) persists the Ollama `model`
and the `secondLanguage` (the non-Polish side of the pair; English default).
`SettingsView` is a SwiftUI `Settings` scene opened via `SettingsLink` in the
menu; its model picker is populated live from `OllamaModelLister` (`ModelListing`,
`GET /api/tags`, derived from the generate endpoint's host). The IDEA.md
invariants (`think:false`, `temperature:0`, `keep_alive`, `endpoint`) stay locked
in `OllamaClient`'s base config and are **not** exposed in the UI.

### Two subtleties that aren't obvious from a single file

1. **The capture poll loop** (`AppCoordinator.captureAndTranslate`): the second
   Cmd+C only *triggers* the copy, so at the instant the double-press is
   detected the new clipboard contents aren't there yet. The monitor samples the
   baseline `changeCount` at the *first* Cmd+C (`registerPress`) — so it precedes
   the second copy even for apps that copy synchronously on keyDown
   (Chromium/Electron, Java) — and hands it to the coordinator via `onDoubleCopy`,
   which polls `readSelection` until `changeCount` rises (default 12ms × 40
   attempts ≈ 480ms, to tolerate slow apps' copies) before streaming.

2. **`DirectionDetector` is UI-only.** `detect(_:second:)` uses
   `NLLanguageRecognizer` (constrained to Polish + the selected second language)
   purely to pick the arrow label (PL→XX / XX→PL). The *actual* translation
   direction is decided by the model from the prompt's swap instruction. The two
   must stay mirrored: Polish input → the selected second language, everything
   else → Polish.

### Config & permissions

`LLMConfig.default` (model `gemma4:26b-mlx`, `think:false`, `temperature:0`,
`keepAlive:"30m"`) lives in `Contracts.swift` and seeds the fresh-install
defaults. At runtime the `model` and the second language come from `SettingsStore`
(UserDefaults) per translation; `think`/`temperature`/`keepAlive`/`endpoint` stay
fixed in `OllamaClient`'s base config. The app is **not sandboxed**
(`Generated/TranslatorMenuBar.entitlements` sets `app-sandbox: false`,
`network.client: true`) because Accessibility is incompatible with MAS
sandboxing. Deployment target is macOS 26.0, Swift 6 (strict concurrency — note
the `MainActor.assumeIsolated` shims around non-isolated AppKit monitor
callbacks).

## Tests

- `Tests/` — fast unit tests, no network, using the fakes in `Tests/Support/`.
- `TestsIntegration/OllamaLiveTests.swift` — hits a real Ollama and **silently
  skips (returns early) when `localhost:11434` is unreachable**, so the suite
  stays green without a running daemon.
- Every test/helper file needs `@testable import TranslatorMenuBar` to see our
  types, and `import Foundation` when it uses Foundation types (e.g. `TimeInterval`).
  Helpers under `Tests/Support/` are easy to forget.
