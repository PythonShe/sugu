#!/bin/bash
# Compiles the bundled data into Data/: prebuilt librime tables and config
# (Data/Rime) and word lists (Data/Lexicon). Needs build-librime.sh and
# fetch-data.sh to have run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/versions.sh"

swift build --package-path "$ROOT/Packages/SuguKit" -c release --product sugu-tool
TOOL="$(swift build --package-path "$ROOT/Packages/SuguKit" -c release --show-bin-path)/sugu-tool"

"$TOOL" build-data \
  --wanxiang "$ROOT/.vendor/wanxiang" \
  --opencc "$ROOT/.vendor/opencc" \
  --out "$ROOT/Data" \
  --version "$WANXIANG_REF"
