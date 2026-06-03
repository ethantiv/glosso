#!/usr/bin/env bash
# Build a Release .app and zip it for a drag-to-/Applications install.
# Free-team signed (Apple Development) — for your own Mac, not notarized.
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
echo "   Rozpakuj i przeciągnij $SCHEME.app do /Applications (pojawi się w Launchpad/Spotlight)."
