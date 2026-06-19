#!/usr/bin/env bash
# Build a Release .app, zip it, and install it into /Applications.
# Signed with the stable self-signed "Glosso Self-Signed" identity (see project.yml) —
# not notarized; first launch on another Mac needs a one-time "Open Anyway".
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="Glosso.xcodeproj"
SCHEME="Glosso"
DEST="platform=macOS,arch=arm64"
DD=".build/dd"
OUT=".build/release"
APP="$DD/Build/Products/Release/$SCHEME.app"
ZIP="$OUT/$SCHEME.zip"

xcodegen generate
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DEST" \
  -configuration Release \
  -derivedDataPath "$DD" \
  -allowProvisioningUpdates \
  -quiet

mkdir -p "$OUT"
rm -f "$ZIP"
# ditto (not zip) preserves the code signature and resource forks.
ditto -c -k --keepParent "$APP" "$ZIP"
echo "✅ Spakowano → $ZIP"

# CI only needs the signed .zip; the local install/launch below is headless-hostile
# (`open` fails with LSOpenURLs -10825 and /Applications isn't writable on the runner).
if [ -n "${CI:-}" ]; then
  echo "CI: pomijam instalację do /Applications."
  exit 0
fi

APP_DEST="/Applications/$SCHEME.app"
if pgrep -xq "$SCHEME"; then
  osascript -e "tell application \"$SCHEME\" to quit" || true
  sleep 1
fi
rm -rf "$APP_DEST"
ditto "$APP" "$APP_DEST"
open "$APP_DEST"
echo "✅ Zainstalowano i uruchomiono → $APP_DEST (pojawi się w Launchpad/Spotlight)."
