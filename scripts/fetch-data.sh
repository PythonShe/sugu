#!/bin/bash
# Downloads the bundled data sources: rime-wanxiang dictionaries
# (CC-BY-4.0) into .vendor/wanxiang, Tatoeba sentences (CC BY 2.0 FR)
# into .vendor/tatoeba, CLDR's Chinese emoji annotations (Unicode-DFS-2016)
# into .vendor/cldr, UniDic's lexicon (BSD) into .vendor/unidic, and CLDR's
# names (Unicode-3.0) into .vendor/cldr-names. scripts/build-data.sh compiles
# them into Data/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/versions.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch_wanxiang() {
  local dest="$ROOT/.vendor/wanxiang"
  if [[ -f "$dest/.ref" && "$(cat "$dest/.ref")" == "$WANXIANG_REF" ]]; then
    echo "wanxiang $WANXIANG_REF already present"
    return
  fi
  curl -fsSL -o "$TMP/wanxiang.tar.gz" \
    "https://codeload.github.com/amzxyz/rime_wanxiang/tar.gz/refs/tags/$WANXIANG_REF"
  echo "$WANXIANG_SHA256  $TMP/wanxiang.tar.gz" | shasum -a 256 -c -
  tar -xzf "$TMP/wanxiang.tar.gz" -C "$TMP"
  local src
  src="$(find "$TMP" -maxdepth 1 -type d -name 'rime*wanxiang-*' | head -1)"
  rm -rf "$dest" && mkdir -p "$dest/dicts"
  for dict in $WANXIANG_DICTS; do
    cp "$src/dicts/$dict.dict.yaml" "$dest/dicts/"
  done
  cp "$src/wanxiang_algebra.yaml" "$src/LICENSE" "$dest/"
  echo "$WANXIANG_REF" > "$dest/.ref"
  echo "wanxiang $WANXIANG_REF -> $dest"
}

fetch_tatoeba() {
  local dest="$ROOT/.vendor/tatoeba"
  if [[ -f "$dest/.ref" && "$(cat "$dest/.ref")" == "$TATOEBA_OPUS_VERSION" && -f "$dest/ja.txt.gz" && -f "$dest/cmn.txt.gz" ]]; then
    echo "Tatoeba $TATOEBA_OPUS_VERSION already present"
    return
  fi
  curl -fsSL -o "$TMP/ja.txt.gz" "https://object.pouta.csc.fi/OPUS-Tatoeba/$TATOEBA_OPUS_VERSION/mono/ja.txt.gz"
  echo "$TATOEBA_JA_SHA256  $TMP/ja.txt.gz" | shasum -a 256 -c -
  curl -fsSL -o "$TMP/cmn.txt.gz" "https://object.pouta.csc.fi/OPUS-Tatoeba/$TATOEBA_OPUS_VERSION/mono/cmn.txt.gz"
  echo "$TATOEBA_CMN_SHA256  $TMP/cmn.txt.gz" | shasum -a 256 -c -
  rm -rf "$dest" && mkdir -p "$dest"
  mv "$TMP/ja.txt.gz" "$TMP/cmn.txt.gz" "$dest/"
  echo "$TATOEBA_OPUS_VERSION" > "$dest/.ref"
  echo "Tatoeba $TATOEBA_OPUS_VERSION -> $dest"
}

fetch_cldr() {
  local dest="$ROOT/.vendor/cldr"
  if [[ -f "$dest/.ref" && "$(cat "$dest/.ref")" == "$CLDR_ANNOTATIONS_REF" ]]; then
    echo "CLDR annotations $CLDR_ANNOTATIONS_REF already present"
    return
  fi
  local base="https://raw.githubusercontent.com/unicode-org/cldr/$CLDR_ANNOTATIONS_REF"
  curl -fsSL -o "$TMP/zh.xml" "$base/common/annotations/zh.xml"
  echo "$CLDR_ANNOTATIONS_ZH_SHA256  $TMP/zh.xml" | shasum -a 256 -c -
  curl -fsSL -o "$TMP/zh_Hant.xml" "$base/common/annotations/zh_Hant.xml"
  echo "$CLDR_ANNOTATIONS_ZH_HANT_SHA256  $TMP/zh_Hant.xml" | shasum -a 256 -c -
  curl -fsSL -o "$TMP/LICENSE" "$base/unicode-license.txt"
  echo "$CLDR_ANNOTATIONS_LICENSE_SHA256  $TMP/LICENSE" | shasum -a 256 -c -
  rm -rf "$dest" && mkdir -p "$dest"
  mv "$TMP/zh.xml" "$TMP/zh_Hant.xml" "$TMP/LICENSE" "$dest/"
  echo "$CLDR_ANNOTATIONS_REF" > "$dest/.ref"
  echo "CLDR annotations $CLDR_ANNOTATIONS_REF -> $dest"
}

fetch_unidic() {
  local dest="$ROOT/.vendor/unidic"
  if [[ -f "$dest/.ref" && "$(cat "$dest/.ref")" == "$UNIDIC_VERSION" ]]; then
    echo "UniDic $UNIDIC_VERSION already present"
    return
  fi
  python3 -I "$ROOT/scripts/fetch-zip-member.py" "$UNIDIC_URL" "$TMP/unidic" lex.csv license/BSD
  echo "$UNIDIC_LEX_SHA256  $TMP/unidic/lex.csv" | shasum -a 256 -c -
  echo "$UNIDIC_BSD_SHA256  $TMP/unidic/BSD" | shasum -a 256 -c -
  rm -rf "$dest" && mkdir -p "$dest"
  mv "$TMP/unidic/lex.csv" "$TMP/unidic/BSD" "$dest/"
  echo "$UNIDIC_VERSION" > "$dest/.ref"
  echo "UniDic $UNIDIC_VERSION -> $dest"
}

fetch_cldr_names() {
  local dest="$ROOT/.vendor/cldr-names"
  if [[ -f "$dest/.ref" && "$(cat "$dest/.ref")" == "$CLDR_NAMES_REF" ]]; then
    echo "CLDR names $CLDR_NAMES_REF already present"
    return
  fi
  local base="https://raw.githubusercontent.com/unicode-org/cldr/$CLDR_NAMES_REF"
  mkdir -p "$TMP/cldr-names"
  local language sum
  for language in de en es fr it ja nl pt; do
    sum="CLDR_NAMES_SHA256_$language"
    curl -fsSL -o "$TMP/cldr-names/$language.xml" "$base/common/main/$language.xml"
    echo "${!sum}  $TMP/cldr-names/$language.xml" | shasum -a 256 -c -
  done
  curl -fsSL -o "$TMP/cldr-names/LICENSE" "$base/LICENSE"
  echo "$CLDR_NAMES_LICENSE_SHA256  $TMP/cldr-names/LICENSE" | shasum -a 256 -c -
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  mv "$TMP/cldr-names" "$dest"
  echo "$CLDR_NAMES_REF" > "$dest/.ref"
  echo "CLDR names $CLDR_NAMES_REF -> $dest"
}

fetch_wanxiang
fetch_tatoeba
fetch_cldr
fetch_unidic
fetch_cldr_names
