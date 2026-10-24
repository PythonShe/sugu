#!/bin/bash
# The full check: the dependencies (scripts/prepare.sh), then the app, the
# package tests, and the benchmark against the budgets in CLAUDE.md. CI runs
# exactly this; it also runs locally without installing or launching
# anything. Hosted runners are slower than a Mac, so with
# SUGU_BUDGETS=report the budgets are measured but do not fail the check.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

scripts/prepare.sh
# The committed notices are what make-notices.sh writes from today's pins.
scripts/make-notices.sh >/dev/null
git diff --exit-code --stat Sugu/Resources/ThirdPartyNotices.txt \
  || { echo "ThirdPartyNotices.txt is out of date: run scripts/make-notices.sh" >&2; exit 1; }

xcodebuild -project Sugu.xcodeproj -scheme Sugu -destination 'platform=macOS,arch=arm64' \
  -configuration Release CODE_SIGNING_ALLOWED=NO -onlyUsePackageVersionsFromResolvedFile build -quiet
PRODUCTS="$(xcodebuild -project Sugu.xcodeproj -scheme Sugu -configuration Release \
  -showBuildSettings 2>/dev/null | awk '$1 == "BUILT_PRODUCTS_DIR" { print $3 }')"
"${PRODUCTS:?}/Sugu.app/Contents/MacOS/Sugu" --measure-draw
# No share-alike file ships in the app (D-072).
if grep -rlis "CC BY-SA\|CC-BY-SA\|ShareAlike" "${PRODUCTS:?}/Sugu.app/Contents/Resources" --exclude=ThirdPartyNotices.txt; then
  echo "share-alike data in the app" >&2; exit 1
fi

xcodebuild -project Sugu.xcodeproj -scheme Sugu -destination 'platform=macOS,arch=arm64' \
  -onlyUsePackageVersionsFromResolvedFile test -quiet
# The settings window and every pane, built offscreen by the debug app.
DEBUG_PRODUCTS="$(xcodebuild -project Sugu.xcodeproj -scheme Sugu -configuration Debug \
  -showBuildSettings 2>/dev/null | awk '$1 == "BUILT_PRODUCTS_DIR" { print $3 }')"
SNAPSHOTS="$(mktemp -d)"
"${DEBUG_PRODUCTS:?}/Sugu.app/Contents/MacOS/Sugu" --snapshot-settings "$SNAPSHOTS"
rm -rf "${SNAPSHOTS:?}"
swift test --package-path Packages/SuguKit
CHECK=--check
[[ "${SUGU_BUDGETS:-}" == report ]] && CHECK=""
# shellcheck disable=SC2086 # CHECK is one flag or none.
swift run --package-path Packages/SuguKit -c release sugu-bench \
  --data Data --bench Bench --json "${SUGU_BENCH_JSON:-/dev/null}" $CHECK
# Fuzz progress goes to stderr; it is shown only when a run fails.
fuzz() {
  local log
  log="$(mktemp)"
  if ! swift run --package-path Packages/SuguKit -c release sugu-bench \
    --data Data --bench Bench --fuzz "$@" 2>"$log"; then
    tail -n 40 "$log" >&2
    rm -f "$log"
    exit 1
  fi
  rm -f "$log"
}
fuzz 200
fuzz 200 --zhuyin
for layout in eten ibm; do
  fuzz 50 --zhuyin --zhuyin-layout "$layout"
done
