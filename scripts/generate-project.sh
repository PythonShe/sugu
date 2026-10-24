#!/bin/bash
# Generates Sugu.xcodeproj from project.yml with SuguKit's pins: Xcode reads
# a workspace's resolved file, not a local package's, and would otherwise
# resolve fresh versions of the packages SuguKit depends on.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate --quiet
PINS=Sugu.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$PINS"
cp Packages/SuguKit/Package.resolved "$PINS/"
