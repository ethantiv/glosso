# Security and performance refactor — verification report

Branch: `codex/security-performance-refactor`, based on `main`. No version change, merge, push or publication.

## Implemented changes

- Reader HTML uses bundled DOMPurify 3.4.15 before DOM insertion, including translated HTML and saved entries. License, upstream reference and SHA-256 checksums are in `Vendor/DOMPurify-README.md`. URL validation, exact HTTPS iframe hosts, sandboxing, CSP and a dedicated WKContentWorld protect the reader and native bridge. Native messages require the current document session, the correct WebView, the main frame and a valid command schema.
- Selection replacement requires a matching process, AX element, range and original text. Unverifiable targets receive only the complete result on the clipboard. Truncated, failed or cancelled streams do not replace text or overwrite the clipboard. Explicit Ollama completion without a reason remains supported. Clipboard restoration checks changeCount.
- ReaderRepository owns file operations outside MainActor and maintains a metadata index. Repeated library refreshes do not read or decode article files. Existing JSON, pins and retention rules remain compatible. Cache writes are atomic; write errors propagate to the UI.
- ReaderRunContext freezes language, provider, model and local fallback model for each operation. Scoped routing shares existing transports and limiter while using those fixed settings. Cancelled operations and obsolete fallback callbacks cannot paint the next article.
- Engine installation accepts injected download/command/filesystem dependencies. Tests verify the signature requirement, Ollama Team ID, failure behavior and staging cleanup without downloading or executing Ollama.
- Keychain operations use an injectable adapter. Saving an empty key now reports a failed deletion instead of returning success.
- All three GitHub Actions workflows were removed: `claude.yml`, `claude-code-review.yml`, `release.yml`. Distribution documentation now describes manual releases.

## Test review

Preserved parser, routing, rate limiter, cancellation, retention, JSON compatibility, keyboard shortcut and window geometry contracts. Kept enum persistence codes and default model checks.

Consolidated or parameterized:

- Removed `SanityTests.directionLabels`; its assertions are covered by the direction table in `SecondLanguageTests`.
- Merged prompt wrapper/instruction duplicates into the action-parameterized PromptBuilder test, retaining checks for both delimiters.
- Parameterized HTTP rejection/server-error cases inside their provider suites. Streaming and one-shot generation remain separate contracts.
- Merged equivalent silent-cloud deadline scenarios across Google and Ollama Cloud; retained fallback and cancellation scenarios.
- Removed duplicate `MockTagsURLProtocol`; each URLSession now uses its own synchronized HTTP fixture registration.

Added regression coverage:

| Area | Tests and observable contract |
| --- | --- |
| HTML injection | ReaderWebSecurityTests: encoded JavaScript URL and data-HTML iframe attacks, dangerous URL schemes/attributes, UI impersonation, sanitized translated/replayed markup, retained formatting and trusted media |
| Native bridge | Actual WKWebView messages from a subframe and an old session are rejected; page-world code cannot reach the isolated handler; malformed commands and foreign WebViews fail validation |
| Replacement | SelectionReplacementTests: changed PID, AX element, range or text; missing AX; changed target during generation; cancellation; explicit nil completion; length/missing/error/late-token completion; clipboard restoration and later user copies |
| Storage and context | ReaderRepositoryTests and ReaderRunContextTests: metadata index reuse, pins/retention, corrupt files, write failures, settings changed mid-article, cache language and late results after cancellation |
| Engine installation | OllamaEngineDownloaderTests: accepted/rejected signatures, strict Team ID requirement, no installation after failure, cleanup after download failure |
| Credentials | APIKeyStoreTests: add/update/read/delete, missing entries, provider account isolation, access denial and failed empty-key deletion |

Test resources have independent preference domains, temporary directories and pasteboards, with cleanup. Shared fake recorders are synchronized. Tests await fake signals and task completion instead of thousands of Task.yield calls. Routing deadlines and clipboard restoration use a manually advanced clock.

`TestsIntegration` is a separate target and `GlossoLive` scheme. Default tests use no real network, model or Keychain. Explicit live runs use environment credentials only:

```sh
scripts/test.sh --adhoc
scripts/test.sh --adhoc --live google
scripts/test.sh --adhoc --live ollama-cloud
scripts/test.sh --adhoc --live local
```

Ad hoc signing is a command-line test override; release signing is unchanged. Live target build-for-testing passed. Invoking Google live tests without GEMINI_API_KEY failed with a readable configuration error before any request. Live providers were not exercised.

## Measurements

macOS 26.5.2, arm64 MacBook Pro. Synthetic articles contain 16 KiB of source text each. Timings are observations, not pass/fail thresholds.

| Articles | Initial metadata index | Ten subsequent list refreshes | Repeated file operations | File operations on main thread |
| ---: | ---: | ---: | ---: | --- |
| 100 | 3.490 ms | 3.037 ms | 0 | No |
| 1000 | 31.273 ms | 28.934 ms | 0 | No |

Measured by `ReaderRepositoryTests.libraryIndexAvoidsRepeatedIOAndRunsOffMain`, result bundle `TestResults-20260921-203727-12663.xcresult`. The index was built exactly once per repository. Initial indexing reads JSON files into lightweight metadata; subsequent refreshes operate entirely on the in-memory index.

## Verification status

- Final offline suite passed: 506 test definitions / 550 parameterized case executions, zero failures and zero skips (`TestResults-20260921-205727-15847.xcresult`), including actual WebKit DOM and navigation tests.
- Final ten repetitions with parallel testing enabled passed: 5500 test-case executions, zero failures or skipped cases (`ParallelTenFinal.xcresult`).
- Historical sanitizer exploits were reproduced during the review. New regression tests assert the corrected contracts; the entire new suite was not backported and run against the pre-refactor revision.
- Manual verification: the user reported that everything works correctly after the changes. This is user-reported verification, not an automated UI result. At the user’s request, do not use Computer Use for Glosso in future work. Earlier Computer Use attempts were inconclusive and are not counted as successful tests.

The final navigation regression test exposed that an inherited optional Swift delegate callback was not exported under WebKit’s Objective-C selector. The callback is now explicitly exported, and a real link click verifies external opening while retaining the reader document. This final correction was verified automatically after the user’s manual test report.
