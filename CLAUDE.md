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
`AccessibilityAuthorizing`, `DoubleKeyDetecting`, `TimeSource`, plus the
`TranslationEvent`/`TranslationError`/`CaptureError` enums and `LLMConfig`).
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
  copied) and that the text is non-empty.
- **LLM** (`Sources/LLM/`) — `OllamaClient` POSTs to `/api/generate` with
  `stream:true`, parses the NDJSON line stream (`NDJSONStreamParser`), and yields
  `.token`/`.finished` through an `AsyncThrowingStream`. `PromptBuilder` carries
  the **PL↔EN swap logic inside the prompt itself**. `prewarm()` is best-effort
  (failures are swallowed) and keeps the model resident via `keep_alive`.
- **Popup** (`Sources/Popup/`) — `TranslationPopupController` shows a borderless
  non-activating `FloatingPanel` that never becomes key (won't steal focus).
  Esc (local monitor) and any click outside (global monitor) dismiss it.

### Two subtleties that aren't obvious from a single file

1. **The capture poll loop** (`AppCoordinator.captureAndTranslate`): the second
   Cmd+C only *triggers* the copy, so at the instant the double-press is
   detected the new clipboard contents aren't there yet. The coordinator records
   the baseline `changeCount`, then polls `readSelection` until it rises (default
   12ms × 20 attempts) before streaming.

2. **`DirectionDetector` is UI-only.** It uses `NLLanguageRecognizer` purely to
   pick the arrow label (PL→EN / EN→PL). The *actual* translation direction is
   decided by the model from the prompt's swap instruction. The two must stay
   mirrored: Polish input → English, everything else → Polish.

### Config & permissions

`LLMConfig.default` (model `gemma4:26b-mlx`, `think:false`, `temperature:0`,
`keepAlive:"30m"`) lives in `Contracts.swift`. The app is **not sandboxed**
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
