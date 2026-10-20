#!/bin/bash
# Writes Sugu/Resources/ThirdPartyNotices.txt from the license files of
# everything the app bundles: SwiftPM checkouts, the librime build sources
# in .vendor/, and pinned license texts for code that ships without one.
# Run after changing a dependency; the output is committed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/versions.sh"

KIT="$ROOT/Packages/SuguKit"
CHECKOUTS="$KIT/.build/checkouts"
RIME="$ROOT/.vendor/librime/src"
CACHE="$ROOT/.vendor/notices"
OUT="$ROOT/Sugu/Resources/ThirdPartyNotices.txt"

swift package --package-path "$KIT" resolve >/dev/null
[[ -d "$RIME/librime" ]] || { echo "run scripts/build-librime.sh first" >&2; exit 1; }
[[ -f "$ROOT/.vendor/wanxiang/LICENSE" && -f "$ROOT/.vendor/cldr/LICENSE" ]] || { echo "run scripts/fetch-data.sh first" >&2; exit 1; }

# fetch <name> <url> <sha256>: a pinned license text, cached in .vendor as
# $CACHE/<name>. Called as a plain statement (not in $(...)), so a failed
# download or checksum stops the script.
fetch() {
  mkdir -p "$CACHE"
  local file="$CACHE/$1"
  [[ -f "$file" ]] && return
  curl -fsSL -o "$file.partial" "$2"
  if ! echo "$3  $file.partial" | shasum -a 256 -c - >/dev/null; then
    rm -f "$file.partial"
    echo "checksum mismatch: $1" >&2
    exit 1
  fi
  mv "$file.partial" "$file"
}

fetch mozc-LICENSE "https://raw.githubusercontent.com/google/mozc/$MOZC_REF/LICENSE" "$MOZC_LICENSE_SHA256"
fetch cldr-LICENSE "https://raw.githubusercontent.com/unicode-org/cldr/$CLDR_REF/LICENSE" "$CLDR_LICENSE_SHA256"
fetch llama.cpp-LICENSE "https://raw.githubusercontent.com/azooKey/llama.cpp/$LLAMA_CPP_REF/LICENSE" "$LLAMA_CPP_LICENSE_SHA256"
fetch sparkle-LICENSE "https://raw.githubusercontent.com/sparkle-project/Sparkle/$SPARKLE_VERSION/LICENSE" "$SPARKLE_LICENSE_SHA256"
fetch cc-by-2.0-fr.html \
  "https://raw.githubusercontent.com/creativecommons/cc-legal-tools-data/$CC_LEGAL_TOOLS_REF/docs/licenses/by/2.0/fr/legalcode.fr.html" \
  "$CC_BY_2_FR_SHA256"
TATOEBA_NOTICE="$CACHE/tatoeba-notice.txt"
{
  echo "Sugu bundles character n-gram statistics computed from Japanese and"
  echo "Mandarin sentences by the contributors of Tatoeba (https://tatoeba.org),"
  echo "taken from the OPUS Tatoeba $TATOEBA_OPUS_VERSION snapshot"
  echo "(https://opus.nlpl.eu/Tatoeba). The sentences themselves are not included."
  echo "Licensed under Creative Commons Paternité 2.0 France:"
  echo
  textutil -convert txt -stdout "$CACHE/cc-by-2.0-fr.html" | sed -n '/^Paternité - 2.0/,$p'
} >"$TATOEBA_NOTICE"

version() {
  python3 -I -c 'import json, sys
pins = json.load(open(sys.argv[1]))["pins"]
print(next(p["state"].get("version") or p["state"]["revision"][:12] for p in pins if p["identity"] == sys.argv[2]))' \
    "$KIT/Package.resolved" "$1"
}

AZOOKEY="$CHECKOUTS/AzooKeyKanaKanjiConverter"
AZOOKEY_DATA="$AZOOKEY/Sources/KanaKanjiConverterModuleWithDefaultDictionary"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
# entry <title> <url> <license> <file>
entry() {
  {
    printf '\n%s\n\n' "================================================================================"
    printf '%s\n%s\nLicense: %s\n\n' "$1" "$2" "$3"
    cat "$4"
  } >>"$TMP"
}

{
  echo "Sugu — Third-Party Notices"
  echo
  echo "Sugu is licensed under the Apache License 2.0. It includes the software"
  echo "and data listed below, each under its own license."
} >"$TMP"

entry "librime $LIBRIME_REF" "https://github.com/rime/librime" "BSD-3-Clause" "$RIME/librime/LICENSE"
entry "librime-octagram" "https://github.com/lotem/librime-octagram" "BSD-3-Clause" "$RIME/librime-octagram/LICENSE"
entry "LevelDB (with librime)" "https://github.com/google/leveldb" "BSD-3-Clause" "$RIME/librime/deps/leveldb/LICENSE"
entry "marisa-trie (with librime and SwiftyMarisa)" "https://github.com/s-yata/marisa-trie" \
  "BSD-2-Clause (chosen from BSD-2-Clause OR LGPL-2.1-or-later)" "$RIME/librime/deps/marisa-trie/COPYING.md"
entry "OpenCC (with librime, including its conversion tables)" "https://github.com/BYVoid/OpenCC" "Apache-2.0" "$RIME/librime/deps/opencc/LICENSE"
entry "yaml-cpp (with librime)" "https://github.com/jbeder/yaml-cpp" "MIT" "$RIME/librime/deps/yaml-cpp/LICENSE"
entry "Boost $BOOST_VERSION (headers, with librime)" "https://www.boost.org" "BSL-1.0" "$RIME/boost/LICENSE_1_0.txt"
entry "rime-wanxiang $WANXIANG_REF (dictionary data, compiled)" "https://github.com/amzxyz/rime_wanxiang" "CC-BY-4.0" "$ROOT/.vendor/wanxiang/LICENSE"
entry "AzooKeyKanaKanjiConverter $(version azookeykanakanjiconverter)" "https://github.com/azooKey/AzooKeyKanaKanjiConverter" "MIT" "$AZOOKEY/LICENSE"
entry "azooKey dictionary data" "https://github.com/ensan-hcl/azooKey_dictionary_storage" "Apache-2.0" "$AZOOKEY_DATA/azooKey_dictionary_storage/LICENSE"
entry "azooKey emoji dictionary: Mozc emoji data" "https://github.com/google/mozc" "BSD-3-Clause" "$CACHE/mozc-LICENSE"
entry "azooKey emoji dictionary: Unicode emoji data and CLDR annotations" "https://www.unicode.org" "Unicode-3.0" "$CACHE/cldr-LICENSE"
entry "CLDR $CLDR_ANNOTATIONS_REF Chinese emoji annotations (as emoji after Chinese words)" "https://cldr.unicode.org" "Unicode-DFS-2016" "$ROOT/.vendor/cldr/LICENSE"
entry "Tatoeba sentences $TATOEBA_OPUS_VERSION (as the Japanese and Chinese language models)" "https://tatoeba.org" "CC-BY-2.0-FR" "$TATOEBA_NOTICE"
entry "llama.cpp $LLAMA_CPP_REF (azooKey build, for Zenzai)" "https://github.com/azooKey/llama.cpp" "MIT" "$CACHE/llama.cpp-LICENSE"
entry "Sparkle $SPARKLE_VERSION" "https://sparkle-project.org" "MIT (bsdiff and other parts: BSD-style, below)" "$CACHE/sparkle-LICENSE"
entry "SwiftyMarisa $(version swiftymarisa)" "https://github.com/ensan-hcl/SwiftyMarisa" \
  "BSD-2-Clause (chosen from BSD-2-Clause OR LGPL)" "$CHECKOUTS/SwiftyMarisa/LICENSE.md"
entry "swift-tokenizers $(version swift-tokenizers)" "https://github.com/ensan-hcl/swift-tokenizers" "Apache-2.0" "$CHECKOUTS/swift-tokenizers/LICENSE"
entry "Jinja $(version jinja)" "https://github.com/johnmai-dev/Jinja" "MIT" "$CHECKOUTS/Jinja/LICENSE"
entry "Swift Algorithms $(version swift-algorithms)" "https://github.com/apple/swift-algorithms" "Apache-2.0" "$CHECKOUTS/swift-algorithms/LICENSE.txt"
entry "Swift Collections $(version swift-collections)" "https://github.com/apple/swift-collections" "Apache-2.0" "$CHECKOUTS/swift-collections/LICENSE.txt"
entry "Swift Numerics $(version swift-numerics)" "https://github.com/apple/swift-numerics" "Apache-2.0" "$CHECKOUTS/swift-numerics/LICENSE.txt"

mv "$TMP" "$OUT"
chmod 644 "$OUT"
trap - EXIT
echo "wrote $OUT ($(wc -l <"$OUT" | tr -d ' ') lines)"
