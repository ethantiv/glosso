# Glosso

A macOS menu-bar app that translates whatever you've selected when you hit **Cmd+C twice in a row**. It uses a local LLM (Gemma via [Ollama](https://ollama.com)) and shows the result in a small panel next to the cursor.

There's no Dock icon — just a bubble in the menu bar. Both Cmd+C presses still copy as usual; the app only listens for the double press, so the only permission it needs is **Accessibility**.

## Requirements

- macOS 26 or later
- [Ollama](https://ollama.com) running locally, with a model installed
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) + Xcode to build

## Build & run

The Xcode project is generated from `project.yml` — don't edit `*.xcodeproj` by hand. The scripts regenerate it for you:

```bash
scripts/run.sh      # build and launch
scripts/test.sh     # run the tests
scripts/package.sh  # build a .zip you can drop into /Applications
```

On first launch the app asks for **Accessibility** permission. That's the only one it needs.

## Using the popup

The panel opens right under the cursor and streams the result as the model produces it.

- **Verbs.** A strip at the top lets you switch what the model does with the selection: **Tłumacz** (translate, the default), **Streść** (summarize into a short bulleted list) and **Popraw** (fix grammar, spelling and punctuation, keeping the original language). Picking a verb re-runs over the same selection — no need to copy again.
- **Tone.** For a translation you can cycle the tone pill between automatic, formal and informal register; it re-translates the same text.
- **Per-word alternatives.** In a finished translation each word is clickable — it opens a dropdown of context-aware alternatives and a "Why?" explanation. Picking one re-translates just that part.
- **Replace.** Paste the result straight back over the still-selected source text.
- **Copy.** Copy the whole result.

You can drag the panel by its body and resize it from the bottom-right grip. Esc closes an open dropdown first, then the panel.

## Settings

From the menu bar you can pick the Ollama model and the second language (English by default; also German, Russian, Spanish, Dutch, French). Polish is always the other side of the pair, and the direction is detected automatically.

Two toggles: **Uczłowiecz tłumaczenia** (default on) makes translations read like natural prose instead of stiff machine output, and **Launch at login** starts the app quietly in the menu bar.

## How it works

The app is split into small modules — hotkey, capture, LLM, popup, settings — each behind a protocol so the pieces stay swappable and testable. For the details, including the design decisions and the reasoning behind them, see [`CLAUDE.md`](CLAUDE.md).
