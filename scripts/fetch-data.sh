#!/bin/bash
# Downloads the bundled dictionary sources (rime-wanxiang, CC-BY-4.0) into
# .vendor/wanxiang. scripts/build-data.sh compiles them into Data/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/versions.sh"

DEST="$ROOT/.vendor/wanxiang"
STAMP="$DEST/.ref"
if [[ -f "$STAMP" && "$(cat "$STAMP")" == "$WANXIANG_REF" ]]; then
  echo "wanxiang $WANXIANG_REF already present"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/wanxiang.tar.gz" \
  "https://codeload.github.com/amzxyz/rime_wanxiang/tar.gz/refs/tags/$WANXIANG_REF"
echo "$WANXIANG_SHA256  $TMP/wanxiang.tar.gz" | shasum -a 256 -c -
tar -xzf "$TMP/wanxiang.tar.gz" -C "$TMP"
SRC="$(find "$TMP" -maxdepth 1 -type d -name 'rime*wanxiang-*' | head -1)"

rm -rf "$DEST" && mkdir -p "$DEST/dicts"
for dict in $WANXIANG_DICTS; do
  cp "$SRC/dicts/$dict.dict.yaml" "$DEST/dicts/"
done
cp "$SRC/wanxiang_algebra.yaml" "$SRC/LICENSE" "$DEST/"
echo "$WANXIANG_REF" > "$STAMP"
echo "wanxiang $WANXIANG_REF -> $DEST"
