#!/bin/bash
# Builds a release: a Developer ID–signed, notarized installer package and a
# notarized, EdDSA-signed archive for Sparkle, with release.json describing
# the archive and the signed appcast. Output goes to dist/. Nothing is
# uploaded: scripts/publish-release.sh publishes it all to
# sugu.zheng-she.com (ADR 0006). The release workflow runs this on CI; it
# runs the same way locally.
#
# Needs, in the environment:
#   TEAM_ID                     Apple developer team
#   DEVELOPER_ID_APPLICATION    e.g. "Developer ID Application: Name (TEAMID)"
#   DEVELOPER_ID_INSTALLER      e.g. "Developer ID Installer: Name (TEAMID)"
#   SPARKLE_PUBLIC_ED_KEY       public key from Sparkle's generate_keys
# and notarization credentials, either
#   NOTARY_PROFILE              a `xcrun notarytool store-credentials` profile
# or an App Store Connect API key:
#   APPLE_API_KEY               path to the .p8
#   APPLE_API_KEY_ID, APPLE_API_ISSUER
# Optional:
#   RELEASE_VERSION             the version being released (from the tag);
#                               the build must carry it
#   KEYCHAIN                    keychain holding the signing identities;
#                               otherwise the search list
#   SPARKLE_PRIVATE_KEY_FILE    otherwise sign_update reads the keychain
#   RELEASE_NOTES_DIR           the notes for the appcast, one Markdown file
#                               per language (scripts/appcast.py)
#   DEVELOPER_ID_PROFILE        name of an installed Developer ID
#                               provisioning profile with Private Cloud Compute
#                               (ADR 0004). Without it the build carries no
#                               entitlement and uses the on-device model only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/versions.sh"
cd "$ROOT"

for name in TEAM_ID DEVELOPER_ID_APPLICATION DEVELOPER_ID_INSTALLER SPARKLE_PUBLIC_ED_KEY; do
  [[ -n "${!name:-}" ]] || { echo "$name is not set" >&2; exit 2; }
done
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${APPLE_API_KEY:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER:-}" ]]; then
  NOTARY_AUTH=(--key "$APPLE_API_KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER")
else
  echo "set NOTARY_PROFILE, or APPLE_API_KEY, APPLE_API_KEY_ID and APPLE_API_ISSUER" >&2; exit 2
fi
SIGN_FLAGS="--timestamp"
PRODUCT_SIGN=(--sign "$DEVELOPER_ID_INSTALLER" --timestamp)
if [[ -n "${KEYCHAIN:-}" ]]; then
  [[ "$KEYCHAIN" != *" "* ]] || { echo "KEYCHAIN must be a path without spaces" >&2; exit 2; }
  SIGN_FLAGS+=" --keychain $KEYCHAIN"
  PRODUCT_SIGN+=(--keychain "$KEYCHAIN")
fi

# A release is built from committed sources, and its build number (what
# Sparkle compares) is yymmddvv from scripts/build-number.sh.
# Untracked files count too: the project takes in whole folders.
[[ -z "$(git status --porcelain)" ]] || { echo "commit or stash changes first, untracked files too" >&2; exit 2; }
BUILD_NUMBER="$(scripts/build-number.sh ${RELEASE_VERSION:+"v$RELEASE_VERSION"})"

DIST="$ROOT/dist"
WORK="$DIST/work"
rm -rf "${WORK:?}" && mkdir -p "$WORK"

# Sparkle's command-line tools, pinned and verified on every release: they
# handle the private key, so no cached copy is trusted.
TOOLS="$WORK/sparkle"
mkdir -p "$TOOLS"
curl -fsSL -o "$WORK/sparkle.tar.xz" \
  "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
echo "$SPARKLE_TOOLS_SHA256  $WORK/sparkle.tar.xz" | shasum -a 256 -c -
tar -xJf "$WORK/sparkle.tar.xz" -C "$TOOLS" ./bin

# Tests and budgets are scripts/ci.sh's, run before tagging; a release only
# builds.
scripts/prepare.sh

# The entitlement is restricted: it ships only with a profile that grants
# it. These settings override any Config/Local.xcconfig.
ENTITLEMENTS=""
[[ -n "${DEVELOPER_ID_PROFILE:-}" ]] && ENTITLEMENTS="Sugu/App/Sugu-PCC.entitlements"
xcodebuild -project Sugu.xcodeproj -scheme Sugu -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$WORK/Sugu.xcarchive" archive -quiet \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  SUGU_ENTITLEMENTS="$ENTITLEMENTS" SUGU_PROFILE="${DEVELOPER_ID_PROFILE:-}" \
  OTHER_CODE_SIGN_FLAGS="$SIGN_FLAGS" SPARKLE_PUBLIC_ED_KEY="$SPARKLE_PUBLIC_ED_KEY" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

APP="$WORK/Sugu.xcarchive/Products/Library/Input Methods/Sugu.app"
# No share-alike file ships in the app (D-072).
if grep -rlis "CC BY-SA\|CC-BY-SA\|ShareAlike" "$APP/Contents/Resources" --exclude=ThirdPartyNotices.txt; then
  echo "share-alike data in the app" >&2; exit 1
fi

# Xcode signs the frameworks it embeds, but not the helpers inside
# Sparkle's, which notarization refuses. Sugu is not sandboxed, so
# Sparkle's XPC services go unused and are removed; the rest is signed
# from the inside out, the app last with the entitlements it was built with.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "${SPARKLE:?}/XPCServices" "${SPARKLE:?}/Versions/B/XPCServices"
for code in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app" "$SPARKLE" "$APP"; do
  # shellcheck disable=SC2086 # SIGN_FLAGS holds several flags.
  codesign --force --options runtime $SIGN_FLAGS --sign "$DEVELOPER_ID_APPLICATION" \
    --preserve-metadata=entitlements "$code"
done

codesign --verify --deep --strict "$APP"
# Every piece of code inside needs the Developer ID signature and a
# timestamp: --verify takes ad-hoc signatures, notarization does not.
while IFS= read -r -d '' code; do
  [[ -d "$code" ]] || file -b "$code" | grep -q "Mach-O" || continue
  info="$(codesign -dvv "$code" 2>&1)" || { echo "unsigned: ${code#"$APP"/}" >&2; exit 1; }
  grep -q "Authority=Developer ID Application" <<<"$info" && grep -q "^Timestamp=" <<<"$info" \
    || { echo "not signed with Developer ID and a timestamp: ${code#"$APP"/}" >&2; exit 1; }
done < <(find "$APP" \( -name "*.app" -o -name "*.framework" -o -name "*.xpc" -o -name "*.dylib" -o \( -type f -perm -u+x \) \) -print0)
SIGNATURE_INFO="$(codesign -dvv "$APP" 2>&1)"
grep -q "Authority=Developer ID Application" <<<"$SIGNATURE_INFO" \
  || { echo "the app is not signed with Developer ID" >&2; exit 1; }
grep -Eq "^(CodeDirectory|Flags).*runtime" <<<"$SIGNATURE_INFO" \
  || { echo "the app is missing the hardened runtime" >&2; exit 1; }
if [[ -n "$ENTITLEMENTS" ]]; then
  codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "com.apple.developer.private-cloud-compute" \
    || { echo "the Private Cloud Compute entitlement is missing" >&2; exit 1; }
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
if [[ -n "${RELEASE_VERSION:-}" && "$RELEASE_VERSION" != "$VERSION" ]]; then
  echo "the build is $VERSION but the release is $RELEASE_VERSION: set MARKETING_VERSION in project.yml" >&2; exit 1
fi

# Gatekeeper must accept what users download.
gatekeeper() {
  local output
  output="$(spctl -a -vvv -t "$1" "$2" 2>&1 || true)"
  echo "$output"
  grep -q "accepted" <<<"$output" || { echo "Gatekeeper rejected $(basename "$2")" >&2; exit 1; }
}

# notarytool exits 0 for a rejected submission too; only "Accepted" passes.
notarize() {
  local output
  # Kept on failure too (a timeout, a rejection), so the log is fetched.
  output="$(xcrun notarytool submit "$1" "${NOTARY_AUTH[@]}" --wait --timeout 30m 2>&1)" || true
  echo "$output"
  if ! grep -q "status: Accepted" <<<"$output"; then
    echo "notarization of $(basename "$1") was not accepted" >&2
    local id
    id="$(awk '$1 == "id:" { print $2; exit }' <<<"$output")"
    [[ -z "$id" ]] || xcrun notarytool log "$id" "${NOTARY_AUTH[@]}" >&2 || true
    exit 1
  fi
}

# Update archive: notarize the app, staple it, then archive the stapled app.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/notarize.zip"
notarize "$WORK/notarize.zip"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
gatekeeper exec "$APP"
ZIP="$DIST/Sugu-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

# Installer package. The bundle is not relocatable, so the installer never
# updates some other copy of Sugu.app instead of /Library/Input Methods,
# and not version checked, so a package always installs its own version,
# an older one too, rather than silently keeping what is there.
STAGE="$WORK/root"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Sugu.app"
pkgbuild --analyze --root "$STAGE" "$WORK/components.plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/components.plist"
plutil -replace 0.BundleIsVersionChecked -bool NO "$WORK/components.plist"
pkgbuild --root "$STAGE" --component-plist "$WORK/components.plist" \
  --install-location "/Library/Input Methods" --scripts "$ROOT/scripts/pkg" \
  --identifier com.zheng-she.inputmethod.Sugu.pkg --version "$VERSION" "$WORK/Sugu-component.pkg"
PKG="$DIST/Sugu-$VERSION.pkg"
productbuild --package "$WORK/Sugu-component.pkg" "${PRODUCT_SIGN[@]}" "$PKG"
notarize "$PKG"
xcrun stapler staple "$PKG"
xcrun stapler validate "$PKG"
gatekeeper install "$PKG"

# The archive's EdDSA signature, then the appcast, signed: the app accepts
# only a signed feed, so the appcast is final here.
SIGN_ARGS=()
[[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]] && SIGN_ARGS=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
ED_SIGNATURE="$("$TOOLS/bin/sign_update" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} -p "$ZIP")"
# The app accepts updates only under the public key built into it; a key
# from another pair would strand every copy of this release.
APP_ED_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")"
swift "$ROOT/scripts/check-ed-signature.swift" "$APP_ED_KEY" "$ED_SIGNATURE" "$ZIP" \
  || { echo "the archive's signature does not match the app's SUPublicEDKey" >&2; exit 1; }
cat >"$DIST/release.json" <<JSON
{
  "version": "$VERSION",
  "build": "$BUILD",
  "minimumSystemVersion": "$MIN_OS",
  "url": "https://sugu.zheng-she.com/releases/$VERSION/$(basename "$ZIP")",
  "length": $(stat -f %z "$ZIP"),
  "edSignature": "$ED_SIGNATURE"
}
JSON
python3 -I "$ROOT/scripts/appcast.py" "$DIST/release.json" "$DIST/appcast.xml" ${RELEASE_NOTES_DIR:+"$RELEASE_NOTES_DIR"}
"$TOOLS/bin/sign_update" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$DIST/appcast.xml"
"$TOOLS/bin/sign_update" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} --verify "$DIST/appcast.xml"

rm -rf "${WORK:?}"
echo "dist: $(basename "$PKG"), $(basename "$ZIP"), release.json, appcast.xml"
