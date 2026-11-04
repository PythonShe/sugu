#!/bin/bash
# Compiles the optional foreign-word download from the latest JMdict and
# Wiktionary (both share-alike, so never bundled) and prints the version,
# checksum and size to put in ModelLibrary.swift's LoanwordDownload. The file
# then goes up to Sugu's site, under models/, before the release that pins it.
#
# usage: build-loanword-download.sh <out-dir>
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:?usage: build-loanword-download.sh <out-dir>}"
[[ -f "$ROOT/.vendor/unidic/lex.csv" ]] || { echo "Missing .vendor/unidic: run scripts/fetch-data.sh first." >&2; exit 1; }
mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL --proto '=https' -o "$TMP/JMdict_e.gz" "https://www.edrdg.org/pub/Nihongo/JMdict_e.gz"
gunzip "$TMP/JMdict_e.gz"
curl -fsSL -o "$TMP/japanese.jsonl" "https://kaikki.org/dictionary/Japanese/kaikki.org-dictionary-Japanese.jsonl"

swift build --package-path "$ROOT/Packages/SuguKit" -c release --product sugu-tool
TOOL="$(swift build --package-path "$ROOT/Packages/SuguKit" -c release --show-bin-path)/sugu-tool"
VERSION="$(date -u +%Y-%m-%d)"
"$TOOL" build-loanword-download --jmdict "$TMP/JMdict_e" --wiktionary "$TMP/japanese.jsonl" \
  --unidic "$ROOT/.vendor/unidic/lex.csv" --out "$TMP/loanwords.bin"

SHA256="$(shasum -a 256 "$TMP/loanwords.bin" | cut -d' ' -f1)"
# The site serves a model only under a name holding its checksum's start, so
# a name is never reused.
FILE="$OUT/loanwords-extended-${SHA256:0:8}.bin"
mv "$TMP/loanwords.bin" "$FILE"

echo "file:    $FILE"
echo "version: $VERSION"
echo "sha256:  $SHA256"
echo "size:    $(wc -c <"$FILE" | tr -d ' ')"
