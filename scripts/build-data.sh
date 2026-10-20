#!/bin/bash
# Compiles the bundled data into Data/: prebuilt librime tables, config and
# the small Chinese grammar model (Data/Rime), word lists (Data/Lexicon) and
# character language models (Data/LM). Needs build-librime.sh and fetch-data.sh to have run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/versions.sh"

[[ -d "$ROOT/.vendor/opencc" ]] || { echo "Missing .vendor/opencc: run scripts/build-librime.sh first." >&2; exit 1; }
[[ -d "$ROOT/.vendor/wanxiang" ]] || { echo "Missing .vendor/wanxiang: run scripts/fetch-data.sh first." >&2; exit 1; }
[[ -d "$ROOT/.vendor/tatoeba" ]] || { echo "Missing .vendor/tatoeba: run scripts/fetch-data.sh first." >&2; exit 1; }

swift build --package-path "$ROOT/Packages/SuguKit" -c release --product sugu-tool
TOOL="$(swift build --package-path "$ROOT/Packages/SuguKit" -c release --show-bin-path)/sugu-tool"

"$TOOL" build-data \
  --wanxiang "$ROOT/.vendor/wanxiang" \
  --opencc "$ROOT/.vendor/opencc" \
  --out "$ROOT/Data" \
  --version "$WANXIANG_REF"

# Language models from Tatoeba (ADR 0005). Bench sentences are left out, so
# the bench measures unseen text.
CORPUS="$(mktemp)"
trap 'rm -f "$CORPUS"' EXIT
gunzip -c "$ROOT/.vendor/tatoeba/ja.txt.gz" >"$CORPUS"
"$TOOL" build-lm --corpus "$CORPUS" --out "$ROOT/Data/LM/ja.lm" \
  --exclude "$ROOT/Bench/ja.tsv" --exclude "$ROOT/Bench/ja-learned.tsv"
gunzip -c "$ROOT/.vendor/tatoeba/cmn.txt.gz" >"$CORPUS"
"$TOOL" build-grammar --corpus "$CORPUS" --opencc "$ROOT/.vendor/opencc" \
  --builder "$ROOT/.vendor/librime/src/librime/build-sugu/plugins/octagram/bin/build_grammar" \
  --out "$ROOT/Data/Rime/sugu-zh-hans.gram" \
  --exclude "$ROOT/Bench/zh.tsv" --exclude "$ROOT/Bench/zh-learned.tsv"
