# Graph Report - .  (2026-07-13)

## Corpus Check
- 120 files · ~72,443 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1241 nodes · 2978 edges · 63 communities (50 shown, 13 thin omitted)
- Extraction: 85% EXTRACTED · 15% INFERRED · 0% AMBIGUOUS · INFERRED: 458 edges (avg confidence: 0.8)
- Token cost: 48,000 input · 9,000 output

## Community Hubs (Navigation)
- Coordinator Flow & Tests
- Ollama Wire Models
- Coordinator Core & Action Cache
- Word Flow & Alternatives Dropdown
- Resize Grip Interaction
- App Delegate & Accessibility
- Engine Provisioning
- Hotkey & Double-Copy Detection
- Prompt Builder Tests
- Floating Panel & Esc Tap
- Settings Store & Login Item
- Popup Model State
- Ollama Client
- Alternatives & Reply Parsers
- Test Suite Imports
- Model Lister Tests
- Design Rationale & Product Rules
- Second Language & Stream Events
- Popup View Rendering
- Selection Guard & Pasteboard
- App Entry & Popup Theme
- Prompt Builder & Formality
- Grammar Diff
- Panel Positioning
- CI Workflows & Release Pipeline
- App State & Model Download
- Esc Key Layering
- Onboarding Wizard
- Direction Detector
- Pull Progress Parser
- Panel Resize & Replace
- Error Enums & Chords
- Ollama Model Manager
- Settings View
- Update Downloader
- Embedded Model Catalog
- Explanation Parser
- NDJSON Stream Parser
- Fix Reason Layout
- Popup Button Styles
- CGEvent Esc Tap Callback
- Popup Phase & Settings Keys
- Translation Errors
- Ollama Client Tests
- Synthetic Cmd+V Replacer
- Polish Spelling Rules
- English Grammar Rules
- Second Language Tests
- Formality Tests
- Code Signing & TCC Grant
- Key Chord
- Model Manager Tests
- Sanity Tests
- Build & Test Config
- Community 55
- Community 56
- Community 57
- Community 58
- Community 59
- Community 60
- Community 61
- Community 62

## God Nodes (most connected - your core abstractions)
1. `FakeLLMClient` - 89 edges
2. `FakePopup` - 89 edges
3. `AppCoordinatorTests` - 74 edges
4. `FakePasteboardReader` - 74 edges
5. `AppCoordinator` - 69 edges
6. `PopupModel` - 50 edges
7. `Foundation` - 43 edges
8. `TranslationPopupController` - 38 edges
9. `SecondLanguage` - 37 edges
10. `PromptBuilderTests` - 37 edges

## Surprising Connections (you probably didn't know these)
- `Panel/Popup signature component (HTML recreation)` --semantically_similar_to--> `Controller-owned popup window sizing`  [INFERRED] [semantically similar]
  DESIGN.md → CLAUDE.md
- `Recorder` --references--> `SecondLanguage`  [EXTRACTED]
  Tests/Support/CoordinatorFakes.swift → Sources/Core/Contracts.swift
- `FakePopup` --references--> `Formality`  [EXTRACTED]
  Tests/Support/CoordinatorFakes.swift → Sources/Core/Contracts.swift
- `Recorder` --references--> `Formality`  [EXTRACTED]
  Tests/Support/CoordinatorFakes.swift → Sources/Core/Contracts.swift
- `FakePopup` --references--> `Action`  [EXTRACTED]
  Tests/Support/CoordinatorFakes.swift → Sources/Core/Contracts.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Version-bump-triggered release pipeline** — project_marketing_version, _github_workflows_release_check_job, _github_workflows_release_import_signing_certificate, _github_workflows_release_update_download_links, docs_distribution_release_trigger, claude_update_check [EXTRACTED 1.00]
- **Preserving the Accessibility (TCC) grant across updates** — claude_self_signed_signing, docs_distribution_stable_self_signed_cert, project_code_sign_identity, project_hardened_runtime_config, claude_update_check [EXTRACTED 1.00]
- **Selection capture and result delivery flow** — claude_double_cmd_c, claude_capture_poll_loop, claude_ax_selection_fallback, claude_direction_detector, claude_headless_in_place_path, claude_synthetic_cmd_v_replace [INFERRED 0.95]

## Communities (63 total, 13 thin omitted)

### Community 0 - "Coordinator Flow & Tests"
Cohesion: 0.09
Nodes (17): AsyncStream, AppCoordinatorTests, Bool, Int, String, FakeAXSelectionReader, FakeEmptyPasteboardReader, FakeHotkeyMonitor (+9 more)

### Community 1 - "Ollama Wire Models"
Cohesion: 0.05
Nodes (42): CodingKey, Decodable, Decoder, Encodable, CodingKeys, done, doneReason, error (+34 more)

### Community 2 - "Coordinator Core & Action Cache"
Cohesion: 0.09
Nodes (31): AnyObject, Never, pid_t, ActionResult, replies, text, AppCoordinator, AsyncThrowingStream (+23 more)

### Community 3 - "Word Flow & Alternatives Dropdown"
Cohesion: 0.06
Nodes (34): Hashable, Identifiable, Layout, LayoutValueKey, PreferenceKey, ProposedViewSize, AlternativeRow, AlternativesDropdown (+26 more)

### Community 4 - "Resize Grip Interaction"
Cohesion: 0.07
Nodes (26): NSRect, NSSize, NSView, NSViewRepresentable, GripView, ResizeGripArea, Bool, CGPoint (+18 more)

### Community 5 - "App Delegate & Accessibility"
Cohesion: 0.06
Nodes (26): ApplicationServices, AXUIElement, CFTypeRef, Notification, NSApplicationDelegate, NSObject, AppDelegate, NSObjectProtocol (+18 more)

### Community 6 - "Engine Provisioning"
Cohesion: 0.09
Nodes (22): Darwin, Process, Sendable, Sendable, EngineStatus, installable, needsDownload, ready (+14 more)

### Community 7 - "Hotkey & Double-Copy Detection"
Cohesion: 0.08
Nodes (21): DoubleKeyDetecting, DoubleCopyDetector, Bool, TimeInterval, GlobalHotkeyMonitor, Any, Bool, Int (+13 more)

### Community 8 - "Prompt Builder Tests"
Cohesion: 0.08
Nodes (4): Bool, PromptBuilderTests, Bool, String

### Community 9 - "Floating Panel & Esc Tap"
Cohesion: 0.11
Nodes (17): CFMachPort, CFRunLoopSource, NSPanel, NSScreen, FloatingPanel, Bool, CGRect, Any (+9 more)

### Community 10 - "Settings Store & Login Item"
Cohesion: 0.13
Nodes (14): ServiceManagement, LoginItemManaging, SettingsStore, Bool, KeyChord, String, UserDefaults, SMAppServiceLoginItem (+6 more)

### Community 11 - "Popup Model State"
Cohesion: 0.15
Nodes (7): PopupModel, Bool, CGFloat, CGSize, Int, String, PopupModelTests

### Community 12 - "Ollama Client"
Cohesion: 0.15
Nodes (13): LLMConfig, Bool, Double, URL, OllamaClient, Bool, Sendable, String (+5 more)

### Community 13 - "Alternatives & Reply Parsers"
Cohesion: 0.11
Nodes (8): AlternativesParser, String, ReplyParser, Bool, String, Substring, AlternativesParserTests, ReplyParserTests

### Community 14 - "Test Suite Imports"
Cohesion: 0.16
Nodes (4): Foundation, Glosso, NaturalLanguage, Testing

### Community 15 - "Model Lister Tests"
Cohesion: 0.10
Nodes (14): MockTagsURLProtocol, OllamaModelListerTests, Bool, Data, HTTPURLResponse, URL, URLRequest, URLRecorder (+6 more)

### Community 16 - "Design Rationale & Product Rules"
Cohesion: 0.09
Nodes (23): Update download links on site step, AX selection fallback with PID snapshot guard, Capture poll loop (changeCount baseline), DirectionDetector translation-direction decision, Double Cmd+C trigger, Headless in-place chord path, In-window SwiftUI alternatives dropdown (not NSPopover), Native /api/generate over OpenAI-compatible /v1 (+15 more)

### Community 17 - "Second Language & Stream Events"
Cohesion: 0.15
Nodes (14): SecondLanguage, dutch, english, french, german, russian, spanish, TranslationEvent (+6 more)

### Community 18 - "Popup View Rendering"
Cohesion: 0.20
Nodes (10): PopupView, ReplyDraftCard, Anchor, Bool, CGRect, CGSize, Int, String (+2 more)

### Community 19 - "Selection Guard & Pasteboard"
Cohesion: 0.15
Nodes (7): SelectionGuard, Int, String, Int, String, SystemPasteboardReader, SelectionGuardTests

### Community 20 - "App Entry & Popup Theme"
Cohesion: 0.12
Nodes (10): App, AppKit, Color, Scene, GlossoApp, OpenSettingsButton, PopupTheme, CGFloat (+2 more)

### Community 21 - "Prompt Builder & Formality"
Cohesion: 0.24
Nodes (6): Formality, automatic, formal, informal, PromptBuilder, String

### Community 22 - "Grammar Diff"
Cohesion: 0.21
Nodes (8): DiffPart, change, same, GrammarDiff, Int, String, GrammarDiffTests, String

### Community 23 - "Panel Positioning"
Cohesion: 0.23
Nodes (10): PanelPositioning, CGFloat, CGPoint, CGRect, CGSize, PanelPositioningTests, Bool, CGPoint (+2 more)

### Community 24 - "CI Workflows & Release Pipeline"
Cohesion: 0.11
Nodes (19): Claude Code @claude mention workflow, Claude Code Review job, Incremental review scope (before..after hunks only), Semantic de-duplication of review findings, check job (version gate), Release workflow (auto-release on merge to main), Action cache + background prefetch, Action palette (verb pills) (+11 more)

### Community 25 - "App State & Model Download"
Cohesion: 0.15
Nodes (15): AppState, Bool, String, URL, EngineProviding, ModelListing, ModelManaging, downloadModel() (+7 more)

### Community 26 - "Esc Key Layering"
Cohesion: 0.15
Nodes (11): EscAction, closeDropdown, closeExplanation, dismiss, passThrough, EscKeyHandling, Bool, NSEvent (+3 more)

### Community 27 - "Onboarding Wizard"
Cohesion: 0.16
Nodes (11): CaseIterable, Int, OnboardingView, Step, language, model, usage, Bool (+3 more)

### Community 28 - "Direction Detector"
Cohesion: 0.20
Nodes (4): NLLanguage, DirectionDetector, String, DirectionDetectorTests

### Community 29 - "Pull Progress Parser"
Cohesion: 0.22
Nodes (9): PullProgress, Int64, Line, PullProgressParser, Result, Bool, Int64, String (+1 more)

### Community 30 - "Panel Resize & Replace"
Cohesion: 0.18
Nodes (4): CoreGraphics, PanelResize, CGSize, PanelResizeTests

### Community 31 - "Error Enums & Chords"
Cohesion: 0.15
Nodes (14): Equatable, Error, CaptureError, emptyOrNonText, nothingSelected, ChordHit, fix, translate (+6 more)

### Community 32 - "Ollama Model Manager"
Cohesion: 0.24
Nodes (8): OllamaModelManager, AsyncThrowingStream, Error, Sendable, String, URL, URLRequest, URLSession

### Community 33 - "Settings View"
Cohesion: 0.30
Nodes (6): Content, Control, SettingsView, Bool, Double, String

### Community 34 - "Update Downloader"
Cohesion: 0.22
Nodes (6): FileManager, String, URL, URLSession, UpdateDownloader, UpdateDownloaderTests

### Community 35 - "Embedded Model Catalog"
Cohesion: 0.24
Nodes (7): EmbeddedModelCatalog, Entry, String, UInt64, EmbeddedModelCatalogTests, Double, UInt64

### Community 36 - "Explanation Parser"
Cohesion: 0.27
Nodes (3): ExplanationParser, String, ExplanationParserTests

### Community 37 - "NDJSON Stream Parser"
Cohesion: 0.25
Nodes (3): NDJSONStreamParser, String, NDJSONStreamParserTests

### Community 38 - "Fix Reason Layout"
Cohesion: 0.29
Nodes (4): FixReasonLayout, Bool, CGFloat, FixReasonLayoutTests

### Community 39 - "Popup Button Styles"
Cohesion: 0.22
Nodes (8): ButtonStyle, ButtonStyleConfiguration, Configuration, Hoverable, IconButtonStyle, LiveDot, SkeletonView, CGFloat

### Community 41 - "CGEvent Esc Tap Callback"
Cohesion: 0.25
Nodes (7): CGEventTapProxy, CGEventType, UInt, UInt16, translationPopupEscTapCallback(), Unmanaged, UnsafeMutableRawPointer

### Community 42 - "Popup Phase & Settings Keys"
Cohesion: 0.22
Nodes (7): Observation, Phase, capturing, done, error, streaming, Key

### Community 43 - "Translation Errors"
Cohesion: 0.22
Nodes (9): Int, TranslationError, cancelled, emptyInput, engineUnavailable, httpStatus, malformedStream, ollamaError (+1 more)

### Community 45 - "Synthetic Cmd+V Replacer"
Cohesion: 0.36
Nodes (5): CGEvent, CGKeyCode, Duration, String, SystemSelectionReplacer

### Community 46 - "Polish Spelling Rules"
Cohesion: 0.36
Nodes (3): PolishSpellingRules, String, PolishSpellingRulesTests

### Community 47 - "English Grammar Rules"
Cohesion: 0.38
Nodes (3): EnglishGrammarRules, String, EnglishGrammarRulesTests

### Community 50 - "Code Signing & TCC Grant"
Cohesion: 0.40
Nodes (5): Import signing certificate step, Stable self-signed identity pins the TCC grant, CI signing secrets (SIGNING_CERT_P12_BASE64 / PASSWORD), Stable self-signed certificate (Glosso Self-Signed), CODE_SIGN_IDENTITY: Glosso Self-Signed

### Community 51 - "Key Chord"
Cohesion: 0.60
Nodes (4): Codable, KeyChord, UInt, String

### Community 54 - "Build & Test Config"
Cohesion: 0.67
Nodes (3): Swift Testing framework (not XCTest), GlossoTests unit-test bundle target, Hardened runtime Release-only / ENABLE_DEBUG_DYLIB: NO

## Knowledge Gaps
- **85 isolated node(s):** `text`, `replies`, `english`, `german`, `russian` (+80 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PopupModel` connect `Popup Model State` to `Coordinator Core & Action Cache`, `Word Flow & Alternatives Dropdown`, `Dropdown Open/Close Tests`, `Floating Panel & Esc Tap`, `Popup Phase & Settings Keys`, `Popup View Rendering`, `Prompt Builder & Formality`, `Grammar Diff`?**
  _High betweenness centrality (0.122) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Test Suite Imports` to `Coordinator Flow & Tests`, `Ollama Wire Models`, `Coordinator Core & Action Cache`, `Engine Provisioning`, `Hotkey & Double-Copy Detection`, `Ollama Client`, `Alternatives & Reply Parsers`, `Model Lister Tests`, `Selection Guard & Pasteboard`, `App Entry & Popup Theme`, `Prompt Builder & Formality`, `Grammar Diff`, `App State & Model Download`, `Pull Progress Parser`, `Panel Resize & Replace`, `Ollama Model Manager`, `Update Downloader`, `Embedded Model Catalog`, `Explanation Parser`, `NDJSON Stream Parser`, `Popup Phase & Settings Keys`?**
  _High betweenness centrality (0.116) - this node is a cross-community bridge._
- **Why does `Formality` connect `Prompt Builder & Formality` to `Coordinator Flow & Tests`, `Coordinator Core & Action Cache`, `App Delegate & Accessibility`, `Engine Provisioning`, `Prompt Builder Tests`, `Floating Panel & Esc Tap`, `Settings Store & Login Item`, `Popup Model State`, `Ollama Client`, `Second Language & Stream Events`, `Popup View Rendering`, `Key Chord`, `Onboarding Wizard`?**
  _High betweenness centrality (0.102) - this node is a cross-community bridge._
- **Are the 69 inferred relationships involving `FakePasteboardReader` (e.g. with `.aSecondDoubleCopyTearsDownTheInFlightStream()` and `.axFallbackBailsWhenFrontmostAppChanged()`) actually correct?**
  _`FakePasteboardReader` has 69 INFERRED edges - model-reasoned connections that need verification._
- **What connects `text`, `replies`, `english` to the rest of the system?**
  _85 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Coordinator Flow & Tests` be split into smaller, more focused modules?**
  _Cohesion score 0.09260429835651074 - nodes in this community are weakly interconnected._
- **Should `Ollama Wire Models` be split into smaller, more focused modules?**
  _Cohesion score 0.053551912568306013 - nodes in this community are weakly interconnected._