#!/usr/bin/env bash
# Run the test suite. `xcodebuild test` builds first, so no separate build needed.
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="Glosso.xcodeproj"
SCHEME="Glosso"
DEST="platform=macOS,arch=arm64"
DD=".build/dd"
RESULT=".build/TestResults.xcresult"

xcodegen generate
# -resultBundlePath must point at a path that does not exist yet.
rm -rf "$RESULT"
xcodebuild test \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DEST" \
  -derivedDataPath "$DD" \
  -resultBundlePath "$RESULT" \
  -allowProvisioningUpdates \
  -quiet
echo "✅ Testy zakończone (wyniki: $RESULT)"
