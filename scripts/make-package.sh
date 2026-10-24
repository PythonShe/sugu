#!/bin/bash
# Builds Sugu's installer package from a built Sugu.app, for
# scripts/release.sh (signed) and scripts/package-dev.sh (unsigned):
#
#   scripts/make-package.sh <Sugu.app> <output.pkg> [productbuild signing flags…]
#
# The installer shows Sugu's license, installs only on the macOS versions
# the app runs on, and only into /Library/Input Methods.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$1"
PKG="$2"
shift 2
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT
mkdir -p "$WORK/root" "$WORK/packages" "$WORK/resources"
ditto "$APP" "$WORK/root/Sugu.app"

# The bundle is not relocatable, so the installer never updates some other
# copy of Sugu.app instead of /Library/Input Methods, and not version
# checked, so a package always installs its own version, an older one too,
# rather than silently keeping what is there.
pkgbuild --analyze --root "$WORK/root" "$WORK/components.plist"
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/components.plist"
plutil -replace 0.BundleIsVersionChecked -bool NO "$WORK/components.plist"
pkgbuild --root "$WORK/root" --component-plist "$WORK/components.plist" \
  --install-location "/Library/Input Methods" --scripts "$ROOT/scripts/pkg" \
  --identifier com.zheng-she.inputmethod.Sugu.pkg --version "$VERSION" "$WORK/packages/Sugu.pkg"

cp "$ROOT/LICENSE" "$WORK/resources/License.txt"
productbuild --synthesize --package "$WORK/packages/Sugu.pkg" "$WORK/distribution.xml"
python3 -I - "$WORK/distribution.xml" "$MIN_OS" <<'PY'
import sys
import xml.etree.ElementTree as ET

path, min_os = sys.argv[1:]
tree = ET.parse(path)
script = tree.getroot()
added = [
    ET.fromstring('<title>Sugu</title>'),
    ET.fromstring('<license file="License.txt"/>'),
    ET.fromstring(f'<allowed-os-versions><os-version min="{min_os}"/></allowed-os-versions>'),
    ET.fromstring('<domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>'),
]
for index, element in enumerate(added):
    script.insert(index, element)
tree.write(path, encoding="utf-8", xml_declaration=True)
PY
productbuild --distribution "$WORK/distribution.xml" --package-path "$WORK/packages" \
  --resources "$WORK/resources" "$@" "$PKG"
