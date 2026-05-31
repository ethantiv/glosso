#!/usr/bin/env bash
# Build, then launch the app. It lives in the menu bar (no Dock icon, no window).
set -euo pipefail
cd "$(dirname "$0")/.."

DD=".build/dd"
APP="$DD/Build/Products/Debug/TranslatorMenuBar.app"

"$(dirname "$0")/build.sh"
open "$APP"
echo "🚀 Uruchomiono. Szukaj ikony dymka w pasku menu (prawy górny róg)."
