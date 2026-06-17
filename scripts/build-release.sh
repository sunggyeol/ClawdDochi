#!/bin/bash
#
# build-release.sh — archive ClawdDochi and export a Developer-ID-signed .app.
#
# IMPORTANT: Exporting with method=developer-id requires a "Developer ID
# Application" certificate in your keychain. That cert is NOT yet installed,
# so the export step will fail until it is. The `archive` step works today with
# automatic Apple Development signing (used for local verification).
#
# Usage:
#   scripts/build-release.sh            # archive + export (needs Developer ID)
#   scripts/build-release.sh --archive-only
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="ClawdDochi"
BUILD_DIR="$ROOT/build/release"
ARCHIVE_PATH="$BUILD_DIR/ClawdDochi.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$ROOT/scripts/ExportOptions.plist"

# Point at a full Xcode install (Command Line Tools alone cannot archive).
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo ">> Archiving $SCHEME ..."
xcodebuild \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=macOS' \
    archive

if [[ "${1:-}" == "--archive-only" ]]; then
    echo ">> Archive complete: $ARCHIVE_PATH"
    exit 0
fi

echo ">> Exporting (method=developer-id) ..."
echo "   NOTE: requires a Developer ID Application certificate."
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

echo ">> Exported app: $EXPORT_DIR/ClawdDochi.app"
