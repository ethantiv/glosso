#!/usr/bin/env bash
# Build, then launch the app. It lives in the menu bar (no Dock icon, no window).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

DD=".build/dd"
APP="$DD/Build/Products/Debug/TranslatorMenuBar.app"

"$SCRIPT_DIR/build.sh"

# Replace any previous instance so the menu bar shows the fresh build.
pkill -f "Debug/TranslatorMenuBar.app/Contents/MacOS/TranslatorMenuBar" 2>/dev/null || true
sleep 1
open -n "$APP"
echo "🚀 Uruchomiono. Szukaj ikony dymka w pasku menu (prawy górny róg)."
