#!/bin/bash
#
# notarize.sh — zip, submit to Apple notary service, staple, and verify.
#
# IMPORTANT: This script is SCAFFOLDED but not run during the autonomous build.
# It requires:
#   * a Developer-ID-signed ClawdDochi.app (see build-release.sh),
#   * a notarytool keychain profile created once with:
#       xcrun notarytool store-credentials "ClawdDochi" \
#         --apple-id "<APPLE_ID>" --team-id "Z7S48Q4N3Z" --password "<APP_SPECIFIC_PW>"
#
# Usage:
#   scripts/notarize.sh path/to/ClawdDochi.app
#
set -euo pipefail

APP_PATH="${1:?usage: notarize.sh <path-to-ClawdDochi.app>}"
PROFILE="${NOTARY_PROFILE:-ClawdDochi}"
ZIP_PATH="${APP_PATH%.app}.zip"

echo ">> Zipping (ditto, keep parent) ..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo ">> Submitting to notary service (profile: $PROFILE) ..."
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$PROFILE" \
    --wait

echo ">> Stapling ticket to the app ..."
xcrun stapler staple "$APP_PATH"

echo ">> Verifying Gatekeeper acceptance ..."
spctl -a -vvv -t install "$APP_PATH"

echo ">> Notarization complete."
