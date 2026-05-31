#!/usr/bin/env bash
# Build the app (Debug). Regenerates the project first so new files are picked up.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="TranslatorMenuBar.xcodeproj"
SCHEME="TranslatorMenuBar"
DEST="platform=macOS,arch=arm64"
DD=".build/dd"

xcodegen generate
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DEST" \
  -configuration Debug \
  -derivedDataPath "$DD" \
  -allowProvisioningUpdates \
  -quiet
echo "✅ Build OK → $DD/Build/Products/Debug/$SCHEME.app"
