#!/usr/bin/env bash
# Offline by default. Live services require an explicit provider and environment credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
SCHEME="Glosso"
EXTRA=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --adhoc) EXTRA+=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual); shift ;;
    --live)
      SCHEME="GlossoLive"
      case "${2:-}" in
        google)
          : "${GEMINI_API_KEY:?Set GEMINI_API_KEY for live Google tests}"
          export TEST_RUNNER_GEMINI_API_KEY="$GEMINI_API_KEY"
          EXTRA+=(-only-testing:GlossoLiveTests/GeminiLiveTests) ;;
        ollama-cloud)
          : "${OLLAMA_API_KEY:?Set OLLAMA_API_KEY for live Ollama Cloud tests}"
          export TEST_RUNNER_OLLAMA_API_KEY="$OLLAMA_API_KEY"
          EXTRA+=(-only-testing:GlossoLiveTests/OllamaCloudLiveTests) ;;
        local) EXTRA+=(-only-testing:GlossoLiveTests/OllamaLiveTests) ;;
        *) echo 'Usage: scripts/test.sh [--adhoc] [--live google|ollama-cloud|local]' >&2; exit 2 ;;
      esac
      shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
RESULT=".build/TestResults-$(date +%Y%m%d-%H%M%S)-$$.xcresult"
xcodegen generate
xcodebuild test -project Glosso.xcodeproj -scheme "$SCHEME" \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/dd \
  -resultBundlePath "$RESULT" "${EXTRA[@]}" -quiet
echo "Testy zakończone (wyniki: $RESULT)"
