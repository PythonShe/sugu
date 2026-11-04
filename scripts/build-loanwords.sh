#!/bin/bash
# Compiles the foreign-word data into Data/Lexicon: the dictionary from UniDic,
# CLDR and the tracked Wikidata extract, and the guesser trained on the same
# pairs. Needs scripts/fetch-data.sh to have run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ -d "$ROOT/.vendor/unidic" && -d "$ROOT/.vendor/cldr-names" ]] || { echo "Missing foreign-word sources: run scripts/fetch-data.sh first." >&2; exit 1; }

swift build --package-path "$ROOT/Packages/SuguKit" -c release --product sugu-tool
TOOL="$(swift build --package-path "$ROOT/Packages/SuguKit" -c release --show-bin-path)/sugu-tool"

WIKIDATA="$(mktemp)"
trap 'rm -f "$WIKIDATA"' EXIT
gunzip -c "$ROOT/scripts/data/wikidata-katakana.tsv.gz" >"$WIKIDATA"
"$TOOL" build-loanwords \
  --unidic "$ROOT/.vendor/unidic/lex.csv" \
  --cldr "$ROOT/.vendor/cldr-names" \
  --wikidata "$WIKIDATA" \
  --out "$ROOT/Data/Lexicon"
