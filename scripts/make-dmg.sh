#!/bin/bash
#
# make-dmg.sh — package a (notarized) ClawdDochi.app into a distributable DMG.
#
# Produces a compressed read-only DMG containing the app plus an /Applications
# symlink for drag-to-install. For a Homebrew cask you may distribute either a
# zip or a dmg; this project's cask references a DMG.
#
# Usage:
#   scripts/make-dmg.sh path/to/ClawdDochi.app [output.dmg]
#
set -euo pipefail

APP_PATH="${1:?usage: make-dmg.sh <path-to-ClawdDochi.app> [output.dmg]}"
APP_NAME="$(basename "$APP_PATH" .app)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo 1.0)"
OUT_DMG="${2:-$(dirname "$APP_PATH")/${APP_NAME}-${VERSION}.dmg}"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

echo ">> Staging contents ..."
cp -R "$APP_PATH" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo ">> Building DMG: $OUT_DMG"
rm -f "$OUT_DMG"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$OUT_DMG"

echo ">> DMG ready: $OUT_DMG"
