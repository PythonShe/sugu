#!/bin/bash
# Builds an installer package of a development build, for testing the
# package install (/Library/Input Methods, the pre- and postinstall
# scripts) on your own Macs. The app is signed as Config/Local.xcconfig
# says (e.g. Apple Development with Private Cloud Compute); the package
# is unsigned and not notarized, so it is not for distribution:
# releases come from scripts/release.sh. Output:
# .build-dev/Sugu-<version>-<build>-dev.pkg, opened in Installer unless
# --no-open is given.
#
# Remove a copy installed by scripts/install-dev.sh first
# (~/Library/Input Methods/Sugu.app): two copies of one input source
# conflict.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DERIVED="$ROOT/.build-dev"

OPEN=1
[[ "${1:-}" == --no-open ]] && OPEN=0

scripts/generate-project.sh
# The build number is yymmddvv, as in releases.
BUILD="$(scripts/build-number.sh)"
xcodebuild -project Sugu.xcodeproj -scheme Sugu -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" build -quiet \
  CURRENT_PROJECT_VERSION="$BUILD"

APP="$DERIVED/Build/Products/Release/Sugu.app"
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

# The same package as scripts/release.sh, unsigned.
rm -f "$DERIVED"/Sugu-*-dev.pkg
PKG="$DERIVED/Sugu-$VERSION-$BUILD-dev.pkg"
scripts/make-package.sh "$APP" "$PKG"
echo "$PKG"
if (( OPEN )); then open "$PKG"; fi
