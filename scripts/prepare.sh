#!/bin/bash
# Gets a checkout ready to build: the native and data dependencies when
# missing, a check that every pinned package has a notice, and the Xcode
# project. scripts/ci.sh and scripts/release.sh start with it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[[ -d Frameworks/librime.xcframework ]] || scripts/build-librime.sh
scripts/fetch-data.sh
[[ -f Data/Rime/build/sugu.table.bin && -f Data/Rime/opencc/emoji.txt && -f Data/LM/ja.lm && -f Data/LM/zh.lm ]] || scripts/build-data.sh

# Every pinned package has an entry in the notices (D-072).
python3 -I -c 'import json, re, sys
pins = [p["identity"] for p in json.load(open(sys.argv[1]))["pins"]]
script = open(sys.argv[2]).read().lower()
missing = [p for p in pins if p not in script]
sys.exit("no notice for: " + ", ".join(missing)) if missing else None' \
  Packages/SuguKit/Package.resolved scripts/make-notices.sh

xcodegen generate --quiet
