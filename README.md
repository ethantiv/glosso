# Glosso

A macOS menu-bar app that translates, fixes, summarizes or answers whatever you have selected when you hit **Cmd+C twice in a row**. It uses a local LLM (Gemma via [Ollama](https://ollama.com)) and shows the result in a small panel next to the cursor. Copy a link instead and it opens the whole article, translated, in a reader window.

No Dock icon, just a bubble in the menu bar. Both Cmd+C presses still copy as usual.

## Install

Grab the latest `Glosso.zip` from [Releases](https://github.com/ethantiv/glosso/releases/latest):

1. Unzip and drag **Glosso.app** to your Applications folder.
2. The first launch is blocked, because the app is signed but not notarized by Apple. Click **Done**, then open **System Settings → Privacy & Security**, scroll to the bottom and click **Open Anyway**. Needed once.
3. Grant **Accessibility** when asked. It's the only permission the app needs.
4. A first-run wizard guides you through downloading a translation model and selecting your languages.

By default everything runs locally. The model and its engine download on first use, so you don't need to install [Ollama](https://ollama.com) yourself (an existing local installation is reused if you have one).

If you'd rather not download a 7–20 GB model, the wizard also offers **Google AI**: the same Gemma models plus Gemini Flash Lite, served by the Gemini API, free, with only an API key to paste. Settings adds a third option, **Ollama Cloud**, which runs the bigger Gemma on Ollama's own servers against your key. Either way the selected text is sent off the machine, so local stays the default.

## Requirements

- macOS 26 or later
- To build from source: [XcodeGen](https://github.com/yonaskolb/XcodeGen) + Xcode

## Build & run

The Xcode project is generated from `project.yml` — don't edit `*.xcodeproj` by hand. The scripts regenerate it for you:

```bash
scripts/run.sh      # build and launch
scripts/test.sh     # run the tests
scripts/package.sh  # build a signed .zip you can drop into /Applications
```

Releasing is automatic: bump `MARKETING_VERSION` in `project.yml` in a PR, and merging it to `main` builds, signs, and publishes the release. See [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md).

## Using the popup

The panel opens under the cursor and streams the result as the model produces it.

- **Verbs.** A strip at the top switches what the model does with the selection: Translate (the default), Fix (grammar, spelling and punctuation, keeping the original language), Reply (drafts a few possible responses to the copied message; pick the one you like) and Summarize (a short bulleted list). Picking a verb re-runs over the same selection, and on the local engine the other verbs are pre-computed in the background, so switching is usually instant.
- **Tone.** For a translation, switch the tone between automatic, formal and informal register. A "What changed?" button names what the switch actually did to the text.
- **Editable source.** Tweak the captured text in place and re-run, instead of copying again.
- **Grammar diff.** Fix highlights what changed; tap a change to learn why, with reasons grounded in Polish Language Council spelling rules or, for English, in a base of mistakes Polish speakers typically make. Past three changes the pane splits into the diff and the clean corrected text, and an eye button hides the diff.
- **Per-word alternatives.** In a finished translation each word is clickable: a dropdown offers context-aware alternatives and a "Why?" explanation. Picking one re-translates just that part, and an undo button brings the previous version back.
- **Replace.** Paste the result straight back over the still-selected source text, or copy it from the header.

## Article reader

Double-press Cmd+C on a bare link and instead of the popup you get a reader window: the article is extracted from the page, summarized in two–three sentences and translated block by block into your primary language. A toolbar switch flips the whole page between the translation and the original, and clicking a single translated paragraph slides its original underneath. A side chat answers questions about the article, with a few suggested ones to start. The window subtitle tracks progress and names the engine that did the work. Translated articles are cached for a week, so reopening the same link is instant.

## In-place shortcuts

Two headless chords act on the current selection without opening the panel and paste the result straight back: **Fix in place** (grammar, default Ctrl+Cmd+G) and **Translate in place** (default Ctrl+Cmd+T). Both are rebindable in Settings.

## Settings

From the menu bar you can pick the engine (local Ollama, Google AI or Ollama Cloud), the model, the primary language (Polish or English) and the second language (Polish, English, German, Russian, Spanish, Dutch or French, or automatic detection). The translation direction is detected per capture. The app's UI language follows your macOS language, independently of these settings.

Either cloud engine reveals a field for its API key ([free from Google AI Studio](https://aistudio.google.com/apikey), or from ollama.com) and a choice of model; the local model stays on screen as the fallback. Keys live in the Keychain, one per provider.

Google AI also shows today's request count, because that tier is metered. Glosso paces itself to each model's own limits: Gemma (the default) gets 30 requests and 16k input tokens per minute and 14 400 per day, Gemini Flash Lite 15 requests and 250k tokens per minute and 500 per day. It waits instead of getting rejected, counts each model's day separately, and hands the work to the local model when the quota runs out.

A **Launch at login** toggle starts the app quietly in the menu bar. **Check for updates…** compares your version against the latest release and downloads the new `.zip` to ~/Downloads; installing is still a manual drag.

## How it works

The app is split into small modules — hotkey, capture, LLM, popup, settings — each behind a protocol. For the details and the reasoning behind the design decisions, see [`CLAUDE.md`](CLAUDE.md).

## License

[MIT](LICENSE)
