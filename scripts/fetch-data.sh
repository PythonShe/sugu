#!/bin/bash
# Downloads the bundled data sources: rime-wanxiang dictionaries
# (CC-BY-4.0) into .vendor/wanxiang, and Tatoeba sentences (CC BY 2.0 FR)
# into .vendor/tatoeba. scripts/build-data.sh compiles them into Data/.
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
  if [[ -f "$dest/.ref" && "$(cat "$dest/.ref")" == "$TATOEBA_OPUS_VERSION" ]]; then
    echo "Tatoeba $TATOEBA_OPUS_VERSION already present"
    return
  fi
  curl -fsSL -o "$TMP/ja.txt.gz" "https://object.pouta.csc.fi/OPUS-Tatoeba/$TATOEBA_OPUS_VERSION/mono/ja.txt.gz"
  echo "$TATOEBA_JA_SHA256  $TMP/ja.txt.gz" | shasum -a 256 -c -
  rm -rf "$dest" && mkdir -p "$dest"
  mv "$TMP/ja.txt.gz" "$dest/"
  echo "$TATOEBA_OPUS_VERSION" > "$dest/.ref"
  echo "Tatoeba $TATOEBA_OPUS_VERSION -> $dest"
}

fetch_wanxiang
fetch_tatoeba
