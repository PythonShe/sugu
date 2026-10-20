#!/bin/bash
# Publishes dist/appcast.xml from scripts/release.sh to the update feed
# (`SUFeedURL`, the sugu-updates R2 bucket behind sugu.zheng-she.com), with
# the release notes in dist/notes/ next to it, once the GitHub release with
# the archive it points at is public: a feed ahead of its archive would
# offer an update that cannot download. A feed for an older build than the
# live one is refused.
#
# Uploads with the AWS CLI when R2_ACCOUNT_ID, R2_ACCESS_KEY_ID and
# R2_SECRET_ACCESS_KEY are set (the release workflow), otherwise with the
# Cloudflare CLI (`cf`), signed in to the account that owns the bucket.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST="$ROOT/dist/appcast.xml"
NOTES="$ROOT/dist/notes"
BUCKET=sugu-updates
FEED="https://sugu.zheng-she.com/appcast.xml"

[[ -f "$APPCAST" ]] || { echo "Missing $APPCAST: run scripts/release.sh first." >&2; exit 1; }
grep -q "sparkle-signatures:" "$APPCAST" || { echo "$APPCAST is not signed." >&2; exit 1; }
build_of() { sed -n 's:.*<sparkle\:version>\([0-9]*\)</sparkle\:version>.*:\1:p' | head -1; }
BUILD="$(build_of <"$APPCAST")"
VERSION="$(sed -n 's:.*<sparkle\:shortVersionString>\([^<]*\)</sparkle\:shortVersionString>.*:\1:p' "$APPCAST" | head -1)"
ARCHIVE="$(sed -n 's/.*<enclosure url="\([^"]*\)".*/\1/p' "$APPCAST")"
[[ -n "$BUILD" && -n "$VERSION" && -n "$ARCHIVE" ]] || { echo "$APPCAST has no version or enclosure." >&2; exit 1; }
curl -fsIL -o /dev/null "$ARCHIVE" || { echo "Not downloadable yet: $ARCHIVE" >&2; exit 1; }

# The live feed, past any cache; none yet before the first release.
live() {
  local body status
  body="$(mktemp)"
  status="$(curl -sS -o "$body" -w '%{http_code}' -H 'Cache-Control: no-cache' "$FEED?$(date +%s)")"
  case "$status" in
    200) build_of <"$body" ;;
    404) ;;
    *) rm -f "$body"; echo "The live feed answered $status." >&2; return 1 ;;
  esac
  rm -f "$body"
}
LIVE="$(live)"
if [[ -n "$LIVE" && "$BUILD" -lt "$LIVE" ]]; then
  echo "The live feed offers build $LIVE, newer than $BUILD." >&2; exit 1
fi

# Notes first, the feed last: a feed that lands has its notes.
if [[ -n "${R2_ACCESS_KEY_ID:-}" ]]; then
  : "${R2_ACCOUNT_ID:?}" "${R2_SECRET_ACCESS_KEY:?}"
  put() {
    AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
      aws --endpoint-url "https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com" --region auto \
      s3 cp "$1" "s3://$BUCKET/$2" --content-type "$3" --cache-control no-cache --only-show-errors
  }
else
  # The Cloudflare CLI sets no Cache-Control; the feed's extension is not
  # one Cloudflare caches by default.
  put() {
    cf r2 objects put "$2" --bucket-name "$BUCKET" --file "$1" --content-type "$3" >/dev/null
  }
fi
if [[ -d "$NOTES" ]]; then
  for file in "$NOTES"/*.md; do
    [[ "$(basename "$file")" == body.md ]] && continue
    put "$file" "notes/$VERSION/$(basename "$file")" "text/markdown; charset=utf-8"
  done
fi
put "$APPCAST" appcast.xml "application/xml"

for _ in $(seq 30); do
  [[ "$(live)" == "$BUILD" ]] && { echo "Published build $BUILD ($VERSION) for $ARCHIVE"; exit 0; }
  sleep 5
done
echo "Uploaded, but $FEED does not serve build $BUILD yet." >&2
exit 1
