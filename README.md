# Glosso

A macOS menu-bar app that translates whatever you've selected when you hit **Cmd+C twice in a row**. It uses a local LLM (Gemma via [Ollama](https://ollama.com)) and shows the result in a small panel next to the cursor.

There's no Dock icon — just a bubble in the menu bar. Both Cmd+C presses still copy as usual; the app only listens for the double press, so the only permission it needs is **Accessibility**.

## Install

Grab the latest `Glosso.zip` from [Releases](https://github.com/ethantiv/glosso/releases/latest):

1. Unzip and drag **Glosso.app** to your Applications folder.
2. Right-click it → **Open** → confirm (once — the app is signed, but not notarized by Apple).
3. Grant **Accessibility** when asked — it's the only permission it needs.
4. A first-run wizard walks you through downloading a translation model and picking your second language.

Everything runs locally. The model and its engine download on first use, so you don't need to install [Ollama](https://ollama.com) yourself (though an existing local Ollama is used if you have one).

When a newer release is out, the menu bar shows a **download** link — drop the new app over the old one and your Accessibility grant carries over.

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

On first launch the app asks for **Accessibility** permission. That's the only one it needs.

Releasing is automatic: bump `MARKETING_VERSION` in `project.yml` in a PR, and merging it to `main` builds, signs, and publishes the release. See [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md).

## Using the popup

The panel opens right under the cursor and streams the result as the model produces it.

- **Verbs.** A strip at the top lets you switch what the model does with the selection: **Tłumacz** (translate, the default), **Streść** (summarize into a short bulleted list) and **Popraw** (fix grammar, spelling and punctuation, keeping the original language). Picking a verb re-runs over the same selection — no need to copy again.
- **Tone.** For a translation you can cycle the tone pill between automatic, formal and informal register; it re-translates the same text.
- **Editable source.** Tweak the captured text in place and re-run the translation, instead of copying again.
- **Grammar diff.** **Popraw** highlights what changed; tap a change to learn why.
- **Per-word alternatives.** In a finished translation each word is clickable — it opens a dropdown of context-aware alternatives and a "Why?" explanation. Picking one re-translates just that part.
- **Replace.** Paste the result straight back over the still-selected source text.
- **Copy.** Copy the whole result.

You can drag the panel by its body and resize it from the bottom-right grip. Esc closes an open dropdown first, then the panel.

## In-place shortcuts

Two headless chords act on the current selection without opening the panel and paste the result straight back: **Popraw w miejscu** (fix grammar, default Ctrl+Cmd+G) and **Tłumacz w miejscu** (translate, default Ctrl+Cmd+T). Both are rebindable in Settings.

## Settings

From the menu bar you can pick the Ollama model and the second language (English by default; also German, Russian, Spanish, Dutch, French). Polish is always the other side of the pair, and the direction is detected automatically.

Two toggles: **Naturalny styl** (default on) makes translations read like natural prose instead of stiff machine output, and **Uruchamiaj przy logowaniu** starts the app quietly in the menu bar. The two in-place shortcuts above are rebindable here too.

## How it works

The app is split into small modules — hotkey, capture, LLM, popup, settings — each behind a protocol so the pieces stay swappable and testable. For the details, including the design decisions and the reasoning behind them, see [`CLAUDE.md`](CLAUDE.md).

## License

[MIT](LICENSE)
