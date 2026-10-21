#!/usr/bin/env bash
# Prints the build number (what Sparkle compares): yymmddvv, the day in UTC
# and the build's place among that day's release tags, from 01.
#
#   scripts/build-number.sh [vX.Y.Z]
#
# With a tag, the day is the tag's and vv counts the release tags made that
# day up to it; without one (dry runs, dev packages) the day is today and vv
# is one past that day's tags.
set -euo pipefail

TAG="${1:-}"
tags_of() {
  TZ=UTC git for-each-ref 'refs/tags/v*' \
    --format='%(creatordate:format-local:%y%m%d) %(creatordate:unix) %(refname:short)' |
    awk -v day="$1" '$1 == day'
}

if [[ -n "$TAG" ]]; then
  read -r DAY STAMP < <(TZ=UTC git for-each-ref "refs/tags/$TAG" \
    --format='%(creatordate:format-local:%y%m%d) %(creatordate:unix)')
  [[ -n "${DAY:-}" ]] || { echo "no tag $TAG" >&2; exit 2; }
  COUNT="$(tags_of "$DAY" | awk -v stamp="$STAMP" '$2 <= stamp' | wc -l)"
else
  DAY="$(TZ=UTC date +%y%m%d)"
  COUNT="$(( $(tags_of "$DAY" | wc -l) + 1 ))"
fi
(( COUNT <= 99 )) || { echo "more than 99 builds on $DAY" >&2; exit 2; }
printf '%s%02d\n' "$DAY" "$COUNT"
