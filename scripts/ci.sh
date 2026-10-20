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
[[ -f Data/Rime/build/sugu.table.bin ]] || scripts/build-data.sh

xcodegen generate --quiet
xcodebuild -project Sugu.xcodeproj -scheme Sugu -destination 'platform=macOS' \
  -configuration Release CODE_SIGNING_ALLOWED=NO build -quiet

swift test --package-path Packages/SuguKit
swift run --package-path Packages/SuguKit -c release sugu-bench \
  --data Data --bench Bench --json "${SUGU_BENCH_JSON:-/dev/null}" --check
