#!/bin/bash
# Publishes the release in dist/ from scripts/release.sh to the sugu-updates
# R2 bucket behind https://sugu.zheng-she.com (ADR 0006):
#
#   releases/<version>/Sugu-<version>.pkg, .zip   the downloads, immutable
#   releases/<version>/notes/<language>.md        the release notes
#   releases.json, latest.json                    every release, and the newest
#   appcast.xml                                   the signed Sparkle feed
#
# in that order, so whatever a reader finds points at files that exist. A
# version already out is never replaced with different files (caches and
# signatures would disagree), and a feed for an older build than the live
# one is refused. Running it again for the same files only finishes what is
# missing.
#
# Uploads with the AWS CLI when R2_ACCOUNT_ID, R2_ACCESS_KEY_ID and
# R2_SECRET_ACCESS_KEY are set (the release workflow), otherwise with the
# Cloudflare CLI (`cf`), signed in to the account that owns the bucket.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
BUCKET=sugu-updates
SITE="https://sugu.zheng-she.com"

fail() { echo "$1" >&2; exit 1; }
for file in appcast.xml release.json; do
  [[ -f "$DIST/$file" ]] || fail "Missing dist/$file: run scripts/release.sh first."
done
grep -q "sparkle-signatures:" "$DIST/appcast.xml" || fail "dist/appcast.xml is not signed."
field() { jq -er ".$1" "$DIST/release.json"; }
VERSION="$(field version)"
BUILD="$(field build)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD" =~ ^[0-9]+$ ]] || fail "release.json has no version or build."
PREFIX="releases/$VERSION"
PKG="$DIST/Sugu-$VERSION.pkg"
ZIP="$DIST/Sugu-$VERSION.zip"
[[ -f "$PKG" && -f "$ZIP" ]] || fail "Missing the package or the archive for $VERSION in dist/."
[[ "$(field url)" == "$SITE/$PREFIX/Sugu-$VERSION.zip" ]] || fail "release.json points somewhere else: $(field url)"
[[ "$(field length)" == "$(wc -c <"$ZIP" | tr -d ' ')" ]] || fail "release.json's length is not the archive's."

# A public file, past any cache: its bytes in $2, or nothing when it is not
# there yet; fails on any other answer.
fetch() {
  local status
  status="$(curl -sS -o "$2" -w '%{http_code}' -H 'Cache-Control: no-cache' "$SITE/$1?$(date +%s)")" || status=none
  case "$status" in
    200) ;;
    404) rm -f "$2" ;;
    *) echo "$SITE/$1 answered $status." >&2; return 1 ;;
  esac
}
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT
build_of() { sed -n 's:.*<sparkle\:version>\([0-9]*\)</sparkle\:version>.*:\1:p' "$1" | head -1; }

if [[ -n "${R2_ACCESS_KEY_ID:-}" ]]; then
  : "${R2_ACCOUNT_ID:?}" "${R2_SECRET_ACCESS_KEY:?}"
  r2() {
    # R2 does not take the checksums newer AWS CLIs send by default.
    AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
      AWS_REQUEST_CHECKSUM_CALCULATION=when_required AWS_RESPONSE_CHECKSUM_VALIDATION=when_required \
      aws --endpoint-url "https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com" --region auto "$@"
  }
  # One PUT per file: R2 refused the CLI's multipart upload of a large
  # file (InvalidPart), and takes up to 5 GB this way.
  put() { r2 s3api put-object --bucket "$BUCKET" --key "$2" --body "$1" --content-type "$3" --cache-control "$4" >/dev/null; }
  # Whether the bucket holds a file, whatever the site serves. Only a
  # "not found" counts as absent; any other failure stops the publish.
  stored() {
    local output
    output="$(r2 s3api head-object --bucket "$BUCKET" --key "$1" 2>&1)" && return 0
    grep -Eq "\(404\)|Not Found" <<<"$output" && return 1
    fail "Could not ask the bucket for $1: $output"
  }
else
  # The Cloudflare CLI sets no Cache-Control; the site's functions do.
  put() {
    cf r2 buckets objects upload "$2" --bucket-name "$BUCKET" --file "$1" --content-type "$3" >/dev/null
  }
  # The bucket is not asked here: a file the site does not serve counts as
  # there, unless FIRST_RELEASE=1 says nothing was published yet.
  stored() { [[ "${FIRST_RELEASE:-}" != 1 ]]; }
fi

# Every check comes before the first upload, so a refused release leaves
# nothing behind. A list the site does not serve counts as empty only
# when the bucket has none either: while the hosting changes, a missing
# answer must not let an older release through.
for file in appcast.xml releases.json; do
  fetch "$file" "$WORK/$file"
  [[ -f "$WORK/$file" ]] || ! stored "$file" || fail "The bucket has $file but $SITE does not serve it."
done
if [[ -f "$WORK/appcast.xml" ]]; then
  LIVE="$(build_of "$WORK/appcast.xml")"
  [[ -z "$LIVE" || "$BUILD" -ge "$LIVE" ]] || fail "The live feed offers build $LIVE, newer than $BUILD."
fi

# Every release, newest first; a release keeps the date it first came out.
[[ -f "$WORK/releases.json" ]] || echo '[]' >"$WORK/releases.json"
jq -e 'type == "array"' "$WORK/releases.json" >/dev/null || fail "The live releases.json is not a list of releases."
TODAY="$(date -u +%Y-%m-%d)"
jq --arg version "$VERSION" --arg today "$TODAY" --arg site "$SITE/$PREFIX" \
  --slurpfile release "$DIST/release.json" '
  ((map(select(.version == $version)) | first | .date) // $today) as $date
  | [{
      version: $version,
      build: ($release[0].build | tonumber),
      date: $date,
      minimumSystemVersion: $release[0].minimumSystemVersion,
      pkg: "\($site)/Sugu-\($version).pkg",
      zip: "\($site)/Sugu-\($version).zip"
    }] + map(select(.version != $version))
  | sort_by(.build) | reverse' "$WORK/releases.json" >"$WORK/releases.new.json"
jq '.[0]' "$WORK/releases.new.json" >"$WORK/latest.json"
[[ "$(jq -r .version "$WORK/latest.json")" == "$VERSION" ]] || fail "A newer release than $VERSION is already listed."

IMMUTABLE="public, max-age=31536000, immutable"

# The downloads: uploaded once, then only ever confirmed. Both are
# compared with what is out before either is uploaded.
MISSING=()
for file in "$PKG" "$ZIP"; do
  key="$PREFIX/$(basename "$file")"
  fetch "$key" "$WORK/live"
  if [[ -f "$WORK/live" ]]; then
    cmp -s "$WORK/live" "$file" || fail "$key is already out with other contents; release a new version instead."
    echo "Already published: $key"
  else
    ! stored "$key" || fail "The bucket has $key but $SITE does not serve it."
    MISSING+=("$file")
  fi
done
for file in ${MISSING[@]+"${MISSING[@]}"}; do
  key="$PREFIX/$(basename "$file")"
  put "$file" "$key" application/octet-stream "$IMMUTABLE"
  fetch "$key" "$WORK/live"
  if [[ ! -f "$WORK/live" ]] || ! cmp -s "$WORK/live" "$file"; then fail "$SITE/$key does not serve what was uploaded."; fi
  echo "Published: $key"
done

if [[ -d "$DIST/notes" ]]; then
  for file in "$DIST"/notes/*.md; do
    [[ -f "$file" && "$(basename "$file")" != body.md ]] || continue
    put "$file" "$PREFIX/notes/$(basename "$file")" "text/markdown; charset=utf-8" no-cache
  done
fi

put "$WORK/releases.new.json" releases.json "application/json" no-cache
put "$WORK/latest.json" latest.json "application/json" no-cache
put "$DIST/appcast.xml" appcast.xml "application/xml" no-cache

for _ in $(seq 30); do
  fetch appcast.xml "$WORK/appcast.xml" || true
  if [[ -f "$WORK/appcast.xml" && "$(build_of "$WORK/appcast.xml")" == "$BUILD" ]]; then
    echo "Published Sugu $VERSION (build $BUILD)."
    exit 0
  fi
  sleep 5
done
fail "Uploaded, but $SITE/appcast.xml does not serve build $BUILD yet."
