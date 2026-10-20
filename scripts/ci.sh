#!/bin/bash
# The full check: builds the native and data dependencies when missing, then
# the app, the package tests, and the benchmark against the budgets in
# CLAUDE.md. CI runs exactly this; it also runs locally without installing
# or launching anything.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[[ -d Frameworks/librime.xcframework ]] || scripts/build-librime.sh
scripts/fetch-data.sh
[[ -f Data/Rime/build/sugu.table.bin && -f Data/Rime/opencc/emoji.txt ]] || scripts/build-data.sh

# Every pinned package has an entry in the notices, and no share-alike
# file ships in the app (D-072).
python3 -I -c 'import json, re, sys
pins = [p["identity"] for p in json.load(open(sys.argv[1]))["pins"]]
script = open(sys.argv[2]).read().lower()
missing = [p for p in pins if p not in script]
sys.exit("no notice for: " + ", ".join(missing)) if missing else None' \
  Packages/SuguKit/Package.resolved scripts/make-notices.sh

xcodegen generate --quiet
xcodebuild -project Sugu.xcodeproj -scheme Sugu -destination 'platform=macOS' \
  -configuration Release CODE_SIGNING_ALLOWED=NO build -quiet
PRODUCTS="$(xcodebuild -project Sugu.xcodeproj -scheme Sugu -configuration Release \
  -showBuildSettings 2>/dev/null | awk '$1 == "BUILT_PRODUCTS_DIR" { print $3 }')"
"${PRODUCTS:?}/Sugu.app/Contents/MacOS/Sugu" --measure-draw
if grep -rlis "CC BY-SA\|CC-BY-SA\|ShareAlike" "${PRODUCTS:?}/Sugu.app/Contents/Resources" --exclude=ThirdPartyNotices.txt; then
  echo "share-alike data in the app" >&2; exit 1
fi

xcodebuild -project Sugu.xcodeproj -scheme Sugu -destination 'platform=macOS' test -quiet
swift test --package-path Packages/SuguKit
swift run --package-path Packages/SuguKit -c release sugu-bench \
  --data Data --bench Bench --json "${SUGU_BENCH_JSON:-/dev/null}" --check
swift run --package-path Packages/SuguKit -c release sugu-bench \
  --data Data --bench Bench --fuzz 200 2>/dev/null
