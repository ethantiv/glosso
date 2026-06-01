# Translator Menu Bar

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

## Settings

From the menu bar you can pick the Ollama model and the second language (English by default; also German, Russian, Spanish, Dutch). Polish is always the other side of the pair, and the direction is detected automatically. There's also a "Launch at login" toggle.

## How it works

The app is split into small modules — hotkey, capture, LLM, popup, settings — each behind a protocol so the pieces stay swappable and testable. For the details, including the design decisions and the reasoning behind them, see [`CLAUDE.md`](CLAUDE.md).
