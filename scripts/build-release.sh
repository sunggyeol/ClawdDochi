#!/bin/bash
#
# build-release.sh — build a Developer-ID-signed ClawdDochi.app ready for
# notarization.
#
# Instead of `xcodebuild archive` + `-exportArchive` (whose export `method`
# handling is brittle across Xcode versions), this does a direct Release build
# with manual Developer ID signing and a secure timestamp, then copies the
# product to build/release/export/ClawdDochi.app. The embedded dochi-cli helper
# is signed on copy with the same identity.
#
# Requires a "Developer ID Application" certificate in the keychain:
#   security find-identity -v -p codesigning | grep "Developer ID Application"
#
# Usage:
#   scripts/build-release.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="ClawdDochi"
TEAM_ID="Z7S48Q4N3Z"
DERIVED="$ROOT/build/release/dd"
EXPORT_DIR="$ROOT/build/release/export"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo ">> Building $SCHEME (Release, Developer ID signing) ..."
xcodebuild \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    -destination 'generic/platform=macOS' \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build

APP_SRC="$DERIVED/Build/Products/Release/ClawdDochi.app"
if [[ ! -d "$APP_SRC" ]]; then
    echo "!! Build product not found at $APP_SRC" >&2
    exit 1
fi

echo ">> Staging signed app ..."
mkdir -p "$EXPORT_DIR"
rm -rf "$EXPORT_DIR/ClawdDochi.app"
cp -R "$APP_SRC" "$EXPORT_DIR/"
APP="$EXPORT_DIR/ClawdDochi.app"

# Re-sign WITHOUT any entitlements so the debug-only get-task-allow entitlement
# (which the build/CodeSignOnCopy injects and which notarization rejects) is
# stripped. Sign the nested helper first, then the outer app bundle. Hardened
# Runtime + secure timestamp are required for notarization.
IDENTITY="Developer ID Application"
echo ">> Re-signing helper + app (stripping get-task-allow) ..."
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Helpers/dochi-cli"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

echo ">> Verifying signature ..."
codesign -dvvv "$APP" 2>&1 | grep -E 'Authority=Developer ID|flags=' || true
for bin in "$APP/Contents/MacOS/ClawdDochi" "$APP/Contents/Helpers/dochi-cli"; do
    if codesign -d --entitlements - "$bin" 2>/dev/null | grep -q "get-task-allow"; then
        echo "!! $bin still has get-task-allow" >&2; exit 1
    fi
done
echo "   no get-task-allow — good"

echo ">> Done: $EXPORT_DIR/ClawdDochi.app"
