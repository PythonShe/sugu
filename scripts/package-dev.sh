#!/bin/bash
# Builds an installer package of a development build, for testing the
# package install (/Library/Input Methods, the pre- and postinstall
# scripts) on your own Macs. The app is signed as Config/Local.xcconfig
# says (e.g. Apple Development with Private Cloud Compute); the package
# is unsigned and not notarized, so it is not for distribution:
# releases come from scripts/release.sh. Output:
# .build-dev/Sugu-<version>-dev.pkg.
#
# Remove a copy installed by scripts/install-dev.sh first
# (~/Library/Input Methods/Sugu.app): two copies of one input source
# conflict.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DERIVED="$ROOT/.build-dev"

xcodegen generate --quiet
# The build number is yymmddvv, as in releases.
xcodebuild -project Sugu.xcodeproj -scheme Sugu -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" build -quiet \
  CURRENT_PROJECT_VERSION="$(scripts/build-number.sh)"

APP="$DERIVED/Build/Products/Release/Sugu.app"
codesign --verify --deep --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

# The same package layout as scripts/release.sh, unsigned.
WORK="$DERIVED/package"
rm -rf "${WORK:?}" && mkdir -p "$WORK/root"
ditto "$APP" "$WORK/root/Sugu.app"
pkgbuild --analyze --root "$WORK/root" "$WORK/components.plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/components.plist"
plutil -replace 0.BundleIsVersionChecked -bool NO "$WORK/components.plist"
PKG="$DERIVED/Sugu-$VERSION-dev.pkg"
pkgbuild --root "$WORK/root" --component-plist "$WORK/components.plist" \
  --install-location "/Library/Input Methods" --scripts "$ROOT/scripts/pkg" \
  --identifier com.zheng-she.inputmethod.Sugu.pkg --version "$VERSION" "$PKG"
rm -rf "${WORK:?}"
echo "$PKG"
