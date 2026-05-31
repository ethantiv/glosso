#!/usr/bin/env bash
# Build, then launch the app. It lives in the menu bar (no Dock icon, no window).
set -euo pipefail
cd "$(dirname "$0")/.."

DD=".build/dd"
APP="$DD/Build/Products/Debug/TranslatorMenuBar.app"

"$(dirname "$0")/build.sh"

# Replace any previous instance so the menu bar shows the fresh build.
pkill -f "Debug/TranslatorMenuBar.app/Contents/MacOS/TranslatorMenuBar" 2>/dev/null || true
sleep 1
open -n "$APP"
echo "🚀 Uruchomiono. Szukaj ikony dymka w pasku menu (prawy górny róg)."
