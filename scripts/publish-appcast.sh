#!/bin/bash
# Publishes dist/appcast.xml from scripts/release.sh to the update feed
# (`SUFeedURL`, the sugu-updates R2 bucket behind sugu.zheng-she.com), once
# the GitHub release with the archive it points at is public: a feed ahead
# of its archive would offer an update that cannot download.
#
# Needs the Cloudflare CLI (`cf`), signed in to the account that owns the
# bucket.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST="$ROOT/dist/appcast.xml"
BUCKET=sugu-updates

[[ -f "$APPCAST" ]] || { echo "Missing $APPCAST: run scripts/release.sh first." >&2; exit 1; }
ARCHIVE="$(sed -n 's/.*<enclosure url="\([^"]*\)".*/\1/p' "$APPCAST")"
[[ -n "$ARCHIVE" ]] || { echo "No enclosure in $APPCAST." >&2; exit 1; }
curl -fsIL -o /dev/null "$ARCHIVE" || { echo "Not downloadable yet: $ARCHIVE" >&2; exit 1; }

cf r2 objects put appcast.xml --bucket-name "$BUCKET" --file "$APPCAST" --content-type application/xml >/dev/null
echo "Published appcast for $ARCHIVE"
