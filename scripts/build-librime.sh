#!/bin/bash
# Builds librime with the octagram plugin and its third-party dependencies as
# one universal static library, packaged as Frameworks/librime.xcframework.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/scripts/versions.sh"

WORK="$ROOT/.vendor/librime"
PREFIX="$WORK/prefix"
OUT="$ROOT/Frameworks/librime.xcframework"

export MACOSX_DEPLOYMENT_TARGET="$SUGU_MACOS_DEPLOYMENT_TARGET"
export CMAKE_OSX_ARCHITECTURES="arm64;x86_64"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
JOBS="$(sysctl -n hw.ncpu)"

checkout() { # name url ref
  local dir="$WORK/src/$1"
  if [[ ! -d "$dir/.git" ]]; then
    git clone --quiet --filter=blob:none "$2" "$dir"
  fi
  git -C "$dir" fetch --quiet --tags origin
  git -C "$dir" checkout --quiet "$3"
}

mkdir -p "$WORK/src" "$PREFIX"

checkout librime https://github.com/rime/librime.git "$LIBRIME_COMMIT"
git -C "$WORK/src/librime" submodule update --init --quiet \
  deps/leveldb deps/marisa-trie deps/opencc deps/yaml-cpp
checkout librime-octagram https://github.com/lotem/librime-octagram.git "$OCTAGRAM_REF"
ln -sfn "$WORK/src/librime-octagram" "$WORK/src/librime/plugins/octagram"

# Boost is header-only for librime.
BOOST_DIR="$WORK/src/boost"
if [[ ! -f "$BOOST_DIR/boost/version.hpp" ]]; then
  tarball="boost_${BOOST_VERSION//./_}.tar.gz"
  curl -fsSL -o "$WORK/$tarball" \
    "https://archives.boost.io/release/$BOOST_VERSION/source/$tarball"
  echo "$BOOST_SHA256  $WORK/$tarball" | shasum -a 256 -c -
  tar -xzf "$WORK/$tarball" -C "$WORK/src"
  rm -rf "$BOOST_DIR"
  mv "$WORK/src/boost_${BOOST_VERSION//./_}" "$BOOST_DIR"
  rm "$WORK/$tarball"
fi

cmake_dep() { # dir [args...]
  local dir="$1"; shift
  cmake -S "$dir" -B "$dir/build-sugu" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -Wno-dev -Wno-deprecated \
    "$@" >/dev/null
  cmake --build "$dir/build-sugu" --target install -j "$JOBS" >/dev/null
}

# AzooKey links its own, older marisa-trie through SwiftyMarisa. Renaming the
# namespace here keeps the two copies from resolving to each other's symbols.
# OpenCC is pointed at the same marisa instead of its bundled 0.2.6.
MARISA_FLAGS="-Dmarisa=rime_marisa -I$PREFIX/include"

DEPS="$WORK/src/librime/deps"
rm -rf "$PREFIX" "$DEPS"/*/build-sugu "$WORK/src/librime/build-sugu"
cmake_dep "$DEPS/leveldb" -DLEVELDB_BUILD_BENCHMARKS=OFF -DLEVELDB_BUILD_TESTS=OFF
cmake_dep "$DEPS/marisa-trie" -DBUILD_TESTING=OFF -DENABLE_TOOLS=OFF \
  -DCMAKE_CXX_FLAGS="$MARISA_FLAGS"
cmake_dep "$DEPS/yaml-cpp" -DYAML_CPP_BUILD_CONTRIB=OFF -DYAML_CPP_BUILD_TESTS=OFF \
  -DYAML_CPP_BUILD_TOOLS=OFF
cmake_dep "$DEPS/opencc" -DBUILD_DOCUMENTATION=OFF -DENABLE_GTEST=OFF \
  -DUSE_SYSTEM_MARISA=ON -DCMAKE_CXX_FLAGS="$MARISA_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="-L$PREFIX/lib"

cmake_dep "$WORK/src/librime" \
  -DBUILD_STATIC=ON \
  -DCMAKE_CXX_FLAGS="$MARISA_FLAGS" \
  -DBUILD_MERGED_PLUGINS=ON \
  -DBUILD_TEST=OFF \
  -DENABLE_LOGGING=OFF \
  -DENABLE_EXTERNAL_PLUGINS=OFF \
  -DBoost_NO_BOOST_CMAKE=TRUE \
  -DBOOST_ROOT="$BOOST_DIR" \
  -DBoost_INCLUDE_DIR="$BOOST_DIR"

# One archive carrying librime and every dependency it links against.
LIBS=("$PREFIX/lib/librime.a" "$PREFIX/lib/libleveldb.a" "$PREFIX/lib/libmarisa.a"
      "$PREFIX/lib/libyaml-cpp.a" "$PREFIX/lib/libopencc.a")
for lib in "${LIBS[@]}"; do [[ -f "$lib" ]] || { echo "missing $lib" >&2; exit 1; }; done
libtool -static -no_warning_for_no_symbols -o "$WORK/librime-all.a" "${LIBS[@]}"
if nm "$WORK/librime-all.a" 2>/dev/null | grep -q "N6marisa"; then
  echo "unrenamed marisa symbols in librime-all.a" >&2; exit 1
fi

HEADERS="$WORK/headers"
rm -rf "$HEADERS" && mkdir -p "$HEADERS"
cp "$PREFIX/include/rime_api.h" "$PREFIX/include/rime_api_deprecated.h" \
   "$PREFIX/include/rime_levers_api.h" "$HEADERS/"
[[ -f "$PREFIX/include/rime_api_stdbool.h" ]] && cp "$PREFIX/include/rime_api_stdbool.h" "$HEADERS/"
cat > "$HEADERS/module.modulemap" <<'EOF'
module CRime {
  header "rime_api.h"
  link "c++"
  export *
}
EOF

rm -rf "$OUT"
xcodebuild -create-xcframework -library "$WORK/librime-all.a" -headers "$HEADERS" \
  -output "$OUT" >/dev/null

# OpenCC conversion tables used by the Simplified/Traditional filters.
mkdir -p "$ROOT/.vendor/opencc"
cp "$PREFIX"/share/opencc/*.json "$PREFIX"/share/opencc/*.ocd2 "$ROOT/.vendor/opencc/"

echo "librime $LIBRIME_REF -> $OUT"
