#!/bin/bash
# Builds Sugu and installs it for the current user only, in
# ~/Library/Input Methods, replacing a running copy. For development
# machines; releases install through the package from scripts/release.sh.
# After the first install, add Sugu in System Settings › Keyboard ›
# Input Sources (it is registered and enabled here).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIGURATION="${1:-Release}"
DERIVED="$ROOT/.build-dev"

scripts/generate-project.sh
xcodebuild -project Sugu.xcodeproj -scheme Sugu -configuration "$CONFIGURATION" \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" build -quiet

DEST="$HOME/Library/Input Methods"
mkdir -p "$DEST"
/usr/bin/pkill -x Sugu || true
rm -rf "${DEST:?}/Sugu.app"
ditto "$DERIVED/Build/Products/$CONFIGURATION/Sugu.app" "$DEST/Sugu.app"
"$DEST/Sugu.app/Contents/MacOS/Sugu" --register
echo "installed $DEST/Sugu.app"
