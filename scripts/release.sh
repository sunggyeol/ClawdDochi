#!/bin/bash
#
# release.sh — one-shot release: archive + Developer-ID export, notarize, staple,
# build a DMG, and print the exact cask edits (version + sha256) to apply.
#
# Prerequisites (one-time):
#   * Apple Developer Program membership
#   * a "Developer ID Application" certificate in your keychain
#       security find-identity -v -p codesigning | grep "Developer ID Application"
#   * a notarytool keychain profile named in $NOTARY_PROFILE (default: ClawdDochi)
#       xcrun notarytool store-credentials "ClawdDochi" \
#         --apple-id "<APPLE_ID>" --team-id "Z7S48Q4N3Z" --password "<APP_PW>"
#
# Usage:
#   scripts/release.sh 1.0        # version is required (used for the DMG name + tag)
#
set -euo pipefail

VERSION="${1:?usage: release.sh <version>   e.g. release.sh 1.0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-ClawdDochi}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

APP="$ROOT/build/release/export/ClawdDochi.app"

echo "==> 1/4  Build + Developer-ID export"
"$ROOT/scripts/build-release.sh"

echo "==> 2/4  Notarize + staple"
NOTARY_PROFILE="$NOTARY_PROFILE" "$ROOT/scripts/notarize.sh" "$APP"

echo "==> 3/4  Build DMG"
DMG="$ROOT/build/release/export/ClawdDochi-${VERSION}.dmg"
"$ROOT/scripts/make-dmg.sh" "$APP" "$DMG"

echo "==> 4/4  Checksum"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

cat <<EOF

============================================================
Release artifact ready:
  $DMG
  sha256: $SHA

Next steps:
  1) Create the GitHub release and upload the DMG:
       gh release create v${VERSION} "$DMG" \\
         --repo sunggyeol/ClawdDochi --title "ClawdDochi ${VERSION}" --notes "Release ${VERSION}"

  2) Edit Casks/clawd-dochi.rb:
       version "${VERSION}"
       sha256 "${SHA}"

  3) Copy Casks/clawd-dochi.rb into the tap repo (homebrew-clawddochi/Casks/)
     and push. Then verify:
       brew tap sunggyeol/clawddochi
       brew audit --cask --online clawd-dochi
       brew install --cask clawd-dochi
============================================================
EOF
