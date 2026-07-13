# Graph Report - glosso  (2026-07-13)

## Corpus Check
- 102 files · ~72,443 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1297 nodes · 3000 edges · 93 communities (52 shown, 41 thin omitted)
- Extraction: 85% EXTRACTED · 15% INFERRED · 0% AMBIGUOUS · INFERRED: 445 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `0b33e3ca`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

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
- Dropdown Open/Close Tests
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
- Panel/Popup signature component (HTML recreation)
- Action cache + background prefetch
- Action palette (verb pills)
- AX selection fallback with PID snapshot guard
- Capture poll loop (changeCount baseline)
- Contracts.swift frozen seam
- DirectionDetector translation-direction decision
- EmbeddedModelCatalog (RAM-fitted recommended tier)
- Headless in-place chord path
- In-window SwiftUI alternatives dropdown (not NSPopover)
- Native /api/generate over OpenAI-compatible /v1
- Controller-owned popup window sizing
- Rule-base grounding for fix reasons (PolishSpellingRules / EnglishGrammarRules)
- Stable self-signed identity pins the TCC grant
- Swift Testing framework (not XCTest)
- Synthesized Cmd+V selection replacement
- think:false invariant
- Best-effort GitHub update check + quarantine-free download
- XcodeGen-generated project (never hand-edit .xcodeproj)
- Reguła Płaskiego Tła (shadow = elevation only)
- Reguła Pełnej Siły Indygo na ciemnym
- Reguła Jednego Eyebrow
- Reguła Systemowego UI (macOS system font in fake UI)
- Not notarized — Open Anyway / quarantine removal
- Version bump is the release trigger
- Stable self-signed certificate (Glosso Self-Signed)
- Jedna decyzja na stronie (single CTA)
- Pokaż gest, nie opowiadaj o nim
- Install flow (unzip, drag, grant Accessibility, wizard)
- Popup verbs Tłumacz / Streść / Popraw

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
- `Recorder` --references--> `SecondLanguage`  [EXTRACTED]
  Tests/Support/CoordinatorFakes.swift → Sources/Core/Contracts.swift
- `FakePopup` --references--> `Formality`  [EXTRACTED]
  Tests/Support/CoordinatorFakes.swift → Sources/Core/Contracts.swift
- `Recorder` --references--> `Formality`  [EXTRACTED]
  Tests/Support/CoordinatorFakes.swift → Sources/Core/Contracts.swift
- `FakePopup` --references--> `Action`  [EXTRACTED]
  Tests/Support/CoordinatorFakes.swift → Sources/Core/Contracts.swift
- `Recorder` --references--> `Action`  [EXTRACTED]
  Tests/Support/CoordinatorFakes.swift → Sources/Core/Contracts.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Version-bump-triggered release pipeline** — project_marketing_version, _github_workflows_release_check_job, _github_workflows_release_import_signing_certificate, _github_workflows_release_update_download_links, docs_distribution_release_trigger, claude_update_check [EXTRACTED 1.00]
- **Preserving the Accessibility (TCC) grant across updates** — claude_self_signed_signing, docs_distribution_stable_self_signed_cert, project_code_sign_identity, project_hardened_runtime_config, claude_update_check [EXTRACTED 1.00]
- **Selection capture and result delivery flow** — claude_double_cmd_c, claude_capture_poll_loop, claude_ax_selection_fallback, claude_direction_detector, claude_headless_in_place_path, claude_synthetic_cmd_v_replace [INFERRED 0.95]

## Communities (93 total, 41 thin omitted)

### Community 0 - "Coordinator Flow & Tests"
Cohesion: 0.07
Nodes (36): AnyObject, Never, pid_t, ActionResult, replies, text, AppCoordinator, AsyncThrowingStream (+28 more)

### Community 1 - "Ollama Wire Models"
Cohesion: 0.09
Nodes (23): CodingKey, Decodable, Model, OllamaModelLister, Sendable, String, URL, URLSession (+15 more)

### Community 2 - "Coordinator Core & Action Cache"
Cohesion: 0.33
Nodes (5): Action, fixGrammar, reply, summarize, translate

### Community 3 - "Word Flow & Alternatives Dropdown"
Cohesion: 0.06
Nodes (34): Hashable, Identifiable, Layout, LayoutValueKey, PreferenceKey, ProposedViewSize, AlternativeRow, AlternativesDropdown (+26 more)

### Community 4 - "Resize Grip Interaction"
Cohesion: 0.07
Nodes (26): NSRect, NSSize, NSView, NSViewRepresentable, GripView, ResizeGripArea, Bool, CGPoint (+18 more)

### Community 5 - "App Delegate & Accessibility"
Cohesion: 0.06
Nodes (26): App, ApplicationServices, AXUIElement, CFTypeRef, Notification, NSApplicationDelegate, NSObject, Scene (+18 more)

### Community 6 - "Engine Provisioning"
Cohesion: 0.09
Nodes (22): Darwin, Process, Sendable, Sendable, EngineStatus, installable, needsDownload, ready (+14 more)

### Community 7 - "Hotkey & Double-Copy Detection"
Cohesion: 0.11
Nodes (18): DoubleKeyDetecting, ChordHit, fix, translate, GlobalHotkeyMonitor, Any, Bool, Int (+10 more)

### Community 8 - "Prompt Builder Tests"
Cohesion: 0.11
Nodes (3): PromptBuilderTests, Bool, String

### Community 9 - "Floating Panel & Esc Tap"
Cohesion: 0.06
Nodes (30): CFMachPort, CFRunLoopSource, CGEvent, CGEventTapProxy, CGEventType, CGKeyCode, Duration, NSPanel (+22 more)

### Community 10 - "Settings Store & Login Item"
Cohesion: 0.13
Nodes (14): ServiceManagement, LoginItemManaging, SettingsStore, Bool, KeyChord, String, UserDefaults, SMAppServiceLoginItem (+6 more)

### Community 11 - "Popup Model State"
Cohesion: 0.07
Nodes (25): ButtonStyle, ButtonStyleConfiguration, Configuration, PopupModel, Bool, CGFloat, CGSize, Int (+17 more)

### Community 12 - "Ollama Client"
Cohesion: 0.17
Nodes (11): OllamaClient, AsyncThrowingStream, Bool, Error, Sendable, String, URL, URLRequest (+3 more)

### Community 13 - "Alternatives & Reply Parsers"
Cohesion: 0.11
Nodes (8): AlternativesParser, String, ReplyParser, Bool, String, Substring, AlternativesParserTests, ReplyParserTests

### Community 14 - "Test Suite Imports"
Cohesion: 0.15
Nodes (4): Foundation, Glosso, NaturalLanguage, Testing

### Community 15 - "Model Lister Tests"
Cohesion: 0.10
Nodes (14): MockTagsURLProtocol, OllamaModelListerTests, Bool, Data, HTTPURLResponse, URL, URLRequest, URLRecorder (+6 more)

### Community 16 - "Design Rationale & Product Rules"
Cohesion: 0.33
Nodes (6): Update download links on site step, Double Cmd+C trigger, Creative North Star: Gest jako bohater, Pinned releases/download/vX.Y.Z/Glosso.zip links, Glosso landing page (docs/index.html), Lokalnie = widoczna wartość (privacy pillar)

### Community 17 - "Second Language & Stream Events"
Cohesion: 0.09
Nodes (12): AsyncStream, TranslationEvent, finished, token, FakeAccessibilityAuthorizing, Recorder, StreamGate, AsyncThrowingStream (+4 more)

### Community 18 - "Popup View Rendering"
Cohesion: 0.08
Nodes (22): Architecture, Build & test, Config & permissions, graphify, Tests, Three subtleties that aren't obvious from a single file, What this is, 1. Create the signing certificate (+14 more)

### Community 19 - "Selection Guard & Pasteboard"
Cohesion: 0.15
Nodes (7): SelectionGuard, Int, String, Int, String, SystemPasteboardReader, SelectionGuardTests

### Community 20 - "App Entry & Popup Theme"
Cohesion: 0.22
Nodes (5): Color, PopupTheme, CGFloat, Double, SwiftUI

### Community 21 - "Prompt Builder & Formality"
Cohesion: 0.20
Nodes (6): Formality, automatic, formal, informal, PromptBuilder, String

### Community 22 - "Grammar Diff"
Cohesion: 0.21
Nodes (8): DiffPart, change, same, GrammarDiff, Int, String, GrammarDiffTests, String

### Community 23 - "Panel Positioning"
Cohesion: 0.23
Nodes (10): PanelPositioning, CGFloat, CGPoint, CGRect, CGSize, PanelPositioningTests, Bool, CGPoint (+2 more)

### Community 24 - "CI Workflows & Release Pipeline"
Cohesion: 0.25
Nodes (8): Claude Code @claude mention workflow, Claude Code Review job, Incremental review scope (before..after hunks only), Semantic de-duplication of review findings, check job (version gate), Release workflow (auto-release on merge to main), Glosso app target (LSUIElement, unsandboxed), MARKETING_VERSION setting

### Community 25 - "App State & Model Download"
Cohesion: 0.23
Nodes (11): AppState, Bool, String, URL, EngineProviding, ModelListing, ModelManaging, OnboardingController (+3 more)

### Community 26 - "Esc Key Layering"
Cohesion: 0.15
Nodes (11): EscAction, closeDropdown, closeExplanation, dismiss, passThrough, EscKeyHandling, Bool, NSEvent (+3 more)

### Community 27 - "Onboarding Wizard"
Cohesion: 0.31
Nodes (5): OnboardingView, Bool, Double, String, Void

### Community 28 - "Direction Detector"
Cohesion: 0.20
Nodes (4): NLLanguage, DirectionDetector, String, DirectionDetectorTests

### Community 29 - "Pull Progress Parser"
Cohesion: 0.22
Nodes (9): PullProgress, Int64, Line, PullProgressParser, Result, Bool, Int64, String (+1 more)

### Community 30 - "Panel Resize & Replace"
Cohesion: 0.19
Nodes (4): CoreGraphics, PanelResize, CGSize, PanelResizeTests

### Community 31 - "Error Enums & Chords"
Cohesion: 0.18
Nodes (11): Equatable, Error, CaptureError, emptyOrNonText, nothingSelected, HotkeyError, accessibilityNotGranted, ModelListingError (+3 more)

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
Cohesion: 0.09
Nodes (22): Decoder, Encodable, CodingKeys, done, doneReason, error, keepAlive, model (+14 more)

### Community 38 - "Fix Reason Layout"
Cohesion: 0.26
Nodes (4): FixReasonLayout, Bool, CGFloat, FixReasonLayoutTests

### Community 39 - "Popup Button Styles"
Cohesion: 0.08
Nodes (23): 1. Overview, 2. Colors, 3. Typography, 4. Elevation, 5. Components, 6. Do's and Don'ts, Buttons, Cards / Containers (+15 more)

### Community 40 - "Dropdown Open/Close Tests"
Cohesion: 0.24
Nodes (6): DoubleCopyDetector, Bool, TimeInterval, DoubleCopyDetectorTests, Bool, TimeInterval

### Community 41 - "CGEvent Esc Tap Callback"
Cohesion: 0.25
Nodes (7): SecondLanguage, dutch, english, french, german, russian, spanish

### Community 42 - "Popup Phase & Settings Keys"
Cohesion: 0.20
Nodes (7): Observation, Phase, capturing, done, error, streaming, Key

### Community 43 - "Translation Errors"
Cohesion: 0.17
Nodes (10): Int, TranslationError, cancelled, emptyInput, engineUnavailable, httpStatus, malformedStream, ollamaError (+2 more)

### Community 45 - "Synthetic Cmd+V Replacer"
Cohesion: 0.33
Nodes (6): CaseIterable, Int, Step, language, model, usage

### Community 46 - "Polish Spelling Rules"
Cohesion: 0.36
Nodes (3): PolishSpellingRules, String, PolishSpellingRulesTests

### Community 47 - "English Grammar Rules"
Cohesion: 0.32
Nodes (3): EnglishGrammarRules, String, EnglishGrammarRulesTests

### Community 48 - "Second Language Tests"
Cohesion: 0.15
Nodes (6): TranslationDirection, fromPolish, toPolish, unknown, SanityTests, SecondLanguageTests

### Community 50 - "Code Signing & TCC Grant"
Cohesion: 0.67
Nodes (3): Import signing certificate step, CI signing secrets (SIGNING_CERT_P12_BASE64 / PASSWORD), CODE_SIGN_IDENTITY: Glosso Self-Signed

### Community 51 - "Key Chord"
Cohesion: 0.31
Nodes (8): Codable, KeyChord, LLMConfig, Bool, Double, UInt, URL, String

### Community 55 - "Community 55"
Cohesion: 0.22
Nodes (8): Accessibility & Inclusion, Anti-references, Brand Personality, Design Principles, Product, Product Purpose, Register, Users

### Community 62 - "Community 62"
Cohesion: 0.40
Nodes (4): downloadModel(), MainActor, Sendable, String

## Knowledge Gaps
- **133 isolated node(s):** `text`, `replies`, `english`, `german`, `russian` (+128 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **41 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Foundation` connect `Test Suite Imports` to `Coordinator Flow & Tests`, `Ollama Wire Models`, `Engine Provisioning`, `Hotkey & Double-Copy Detection`, `Ollama Client`, `Alternatives & Reply Parsers`, `Model Lister Tests`, `Selection Guard & Pasteboard`, `Prompt Builder & Formality`, `Grammar Diff`, `Pull Progress Parser`, `Panel Resize & Replace`, `Error Enums & Chords`, `Ollama Model Manager`, `Update Downloader`, `Embedded Model Catalog`, `Explanation Parser`, `NDJSON Stream Parser`, `Dropdown Open/Close Tests`, `Popup Phase & Settings Keys`, `Ollama Client Tests`, `Community 62`?**
  _High betweenness centrality (0.115) - this node is a cross-community bridge._
- **Why does `PopupModel` connect `Popup Model State` to `Coordinator Core & Action Cache`, `Word Flow & Alternatives Dropdown`, `Floating Panel & Esc Tap`, `Popup Phase & Settings Keys`, `Second Language Tests`, `Prompt Builder & Formality`, `Grammar Diff`?**
  _High betweenness centrality (0.114) - this node is a cross-community bridge._
- **Why does `Formality` connect `Prompt Builder & Formality` to `Coordinator Flow & Tests`, `Engine Provisioning`, `Prompt Builder Tests`, `Floating Panel & Esc Tap`, `Settings Store & Login Item`, `Popup Model State`, `Ollama Client`, `Synthetic Cmd+V Replacer`, `Second Language & Stream Events`, `Key Chord`, `Error Enums & Chords`?**
  _High betweenness centrality (0.093) - this node is a cross-community bridge._
- **Are the 69 inferred relationships involving `FakePasteboardReader` (e.g. with `.aSecondDoubleCopyTearsDownTheInFlightStream()` and `.axFallbackBailsWhenFrontmostAppChanged()`) actually correct?**
  _`FakePasteboardReader` has 69 INFERRED edges - model-reasoned connections that need verification._
- **What connects `text`, `replies`, `english` to the rest of the system?**
  _133 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Coordinator Flow & Tests` be split into smaller, more focused modules?**
  _Cohesion score 0.06961140620631814 - nodes in this community are weakly interconnected._
- **Should `Ollama Wire Models` be split into smaller, more focused modules?**
  _Cohesion score 0.09041835357624832 - nodes in this community are weakly interconnected._