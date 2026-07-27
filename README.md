# Glosso

A macOS menu-bar app that translates whatever you have selected when you hit **Cmd+C twice in a row**. It uses a local LLM (Gemma via [Ollama](https://ollama.com)) and shows the result in a small panel next to the cursor.

No Dock icon, just a bubble in the menu bar. Both Cmd+C presses still copy as usual.

## Install

Grab the latest `Glosso.zip` from [Releases](https://github.com/ethantiv/glosso/releases/latest):

1. Unzip and drag **Glosso.app** to your Applications folder.
2. Right-click it → **Open** → confirm (once; the app is signed, but not notarized by Apple).
3. Grant **Accessibility** when asked. It's the only permission the app needs.
4. A first-run wizard guides you through downloading a translation model and selecting your languages.

By default everything runs locally. The model and its engine download on first use, so you don't need to install [Ollama](https://ollama.com) yourself (an existing local installation is reused if you have one).

If you'd rather not download a 7–20 GB model, the wizard also offers **Google AI**: the same Gemma models served by the Gemini API, free, with only an API key to paste. In that mode the selected text is sent to Google. Local stays the default.

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

- **Verbs.** A strip at the top switches what the model does with the selection: **Translate** (the default), **Summarize** (a short bulleted list), **Fix** (grammar, spelling and punctuation, keeping the original language) and **Reply** (drafts a few possible responses to the copied message; pick the one you like). Picking a verb re-runs over the same selection.
- **Tone.** For a translation, cycle the tone pill between automatic, formal and informal register.
- **Editable source.** Tweak the captured text in place and re-run, instead of copying again.
- **Grammar diff.** **Fix** highlights what changed; tap a change to learn why.
- **Per-word alternatives.** In a finished translation each word is clickable: a dropdown offers context-aware alternatives and a "Why?" explanation. Picking one re-translates just that part.
- **Replace.** Paste the result straight back over the still-selected source text.

## Article reader

Double-press Cmd+C on a bare link and instead of the popup you get a reader window: the article is extracted from the page, summarized in two–three sentences and translated block by block into your primary language. An eye toggle flips between the translation and the original, and a side chat lets you ask questions about the article (with a few suggested ones to start). Translated articles are cached for a week, so reopening the same link is instant.

## In-place shortcuts

Two headless chords act on the current selection without opening the panel and paste the result straight back: **Fix in place** (grammar, default Ctrl+Cmd+G) and **Translate in place** (default Ctrl+Cmd+T). Both are rebindable in Settings.

## Settings

From the menu bar you can pick the engine (local Ollama or Google AI), the model, the primary language (Polish or English) and the second language (English, German, Russian, Spanish, Dutch or French, or automatic detection). The translation direction is detected per capture. The app's UI language follows your macOS language, independently of these settings.

Picking **Google AI** reveals a field for the API key ([free from Google AI Studio](https://aistudio.google.com/apikey)), a choice of Gemma tier and today's request count. The key is stored in the Keychain. Glosso paces itself to the free tier's limits — 30 requests and 16k input tokens per minute, 14 400 requests per day — waiting rather than getting rejected, and it falls back to the local model when the daily quota runs out.

A **Launch at login** toggle starts the app quietly in the menu bar.

## How it works

The app is split into small modules — hotkey, capture, LLM, popup, settings — each behind a protocol. For the details and the reasoning behind the design decisions, see [`CLAUDE.md`](CLAUDE.md).

## License

[MIT](LICENSE)
