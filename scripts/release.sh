#!/bin/bash
# Builds a release: a Developer ID–signed, notarized installer package and a
# notarized, EdDSA-signed archive with its appcast entry for Sparkle. Output
# goes to dist/. Nothing is uploaded.
#
# Needs, in the environment:
#   TEAM_ID                     Apple developer team
#   DEVELOPER_ID_APPLICATION    e.g. "Developer ID Application: Name (TEAMID)"
#   DEVELOPER_ID_INSTALLER      e.g. "Developer ID Installer: Name (TEAMID)"
#   NOTARY_PROFILE              a `xcrun notarytool store-credentials` profile
#   SPARKLE_PUBLIC_ED_KEY       public key from Sparkle's generate_keys
#   SPARKLE_PRIVATE_KEY_FILE    optional; otherwise sign_update reads the keychain
#   DEVELOPER_ID_PROFILE        optional; name of an installed Developer ID
#                               provisioning profile with Private Cloud Compute
#                               (ADR 0004). Without it the build carries no
#                               entitlement and uses the on-device model only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/versions.sh"
cd "$ROOT"

for name in TEAM_ID DEVELOPER_ID_APPLICATION DEVELOPER_ID_INSTALLER NOTARY_PROFILE SPARKLE_PUBLIC_ED_KEY; do
  [[ -n "${!name:-}" ]] || { echo "$name is not set" >&2; exit 2; }
done

DIST="$ROOT/dist"
WORK="$DIST/work"
rm -rf "${WORK:?}" && mkdir -p "$WORK"

# Sparkle's command-line tools, pinned and verified.
TOOLS="$ROOT/.vendor/sparkle-$SPARKLE_VERSION"
if [[ ! -x "$TOOLS/bin/sign_update" ]]; then
  mkdir -p "$TOOLS"
  curl -fsSL -o "$WORK/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  echo "$SPARKLE_TOOLS_SHA256  $WORK/sparkle.tar.xz" | shasum -a 256 -c -
  tar -xJf "$WORK/sparkle.tar.xz" -C "$TOOLS" ./bin
fi

# Dependencies, tests and budgets first.
scripts/ci.sh

# The entitlement is restricted: it ships only with a profile that grants
# it. These settings override any Config/Local.xcconfig.
ENTITLEMENTS=""
[[ -n "${DEVELOPER_ID_PROFILE:-}" ]] && ENTITLEMENTS="Sugu/App/Sugu-PCC.entitlements"
xcodebuild -project Sugu.xcodeproj -scheme Sugu -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$WORK/Sugu.xcarchive" archive -quiet \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  SUGU_ENTITLEMENTS="$ENTITLEMENTS" SUGU_PROFILE="${DEVELOPER_ID_PROFILE:-}" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY"

APP="$WORK/Sugu.xcarchive/Products/Library/Input Methods/Sugu.app"
codesign --verify --deep --strict "$APP"
if [[ -n "$ENTITLEMENTS" ]]; then
  codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "com.apple.developer.private-cloud-compute" \
    || { echo "the Private Cloud Compute entitlement is missing" >&2; exit 1; }
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"

notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

# Update archive: notarize the app, staple it, then archive the stapled app.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/notarize.zip"
notarize "$WORK/notarize.zip"
xcrun stapler staple "$APP"
ZIP="$DIST/Sugu-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# Installer package. The bundle is not relocatable, so the installer never
# updates some other copy of Sugu.app instead of /Library/Input Methods.
STAGE="$WORK/root"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Sugu.app"
pkgbuild --analyze --root "$STAGE" "$WORK/components.plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/components.plist"
pkgbuild --root "$STAGE" --component-plist "$WORK/components.plist" \
  --install-location "/Library/Input Methods" --scripts "$ROOT/scripts/pkg" \
  --identifier com.zheng-she.inputmethod.Sugu.pkg --version "$VERSION" "$WORK/Sugu-component.pkg"
PKG="$DIST/Sugu-$VERSION.pkg"
productbuild --package "$WORK/Sugu-component.pkg" --sign "$DEVELOPER_ID_INSTALLER" --timestamp "$PKG"
notarize "$PKG"
xcrun stapler staple "$PKG"

# Appcast with the new version; Sparkle needs only the latest item.
SIGN_ARGS=()
[[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]] && SIGN_ARGS=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
SIGNATURE="$("$TOOLS/bin/sign_update" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$ZIP")"
cat >"$DIST/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Sugu</title>
    <item>
      <title>$VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/PythonShe/sugu/releases/download/v$VERSION/Sugu-$VERSION.zip" $SIGNATURE type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

rm -rf "${WORK:?}"
echo "dist: $(basename "$PKG"), $(basename "$ZIP"), appcast.xml"
