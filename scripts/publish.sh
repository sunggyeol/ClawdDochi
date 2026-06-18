#!/bin/bash
#
# publish.sh — one command to ship a new ClawdDochi version end to end:
#   1. build + Developer-ID sign + notarize + DMG  (scripts/release.sh)
#   2. create/update the GitHub Release and upload the DMG
#   3. bump the cask (version + sha256 + url) and push it to the tap repo
#
# Signing/notarization run LOCALLY using your keychain — no certificates,
# passwords, or other secrets ever touch a Git repo. The only things published
# are the (already public) DMG and the cask file.
#
# Prerequisites (see scripts/release.sh): Developer ID cert installed + a
# notarytool keychain profile named "ClawdDochi". You must also be logged in to
# the GitHub CLI (`gh auth status`).
#
# Usage:
#   scripts/publish.sh 1.1
#
set -euo pipefail

VERSION="${1:?usage: publish.sh <version>   e.g. publish.sh 1.1}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_REPO="sunggyeol/ClawdDochi"
TAP_REPO="sunggyeol/homebrew-clawddochi"
CASK="$ROOT/Casks/clawd-dochi.rb"
DMG="$ROOT/build/release/export/ClawdDochi-${VERSION}.dmg"

echo "==> Build + sign + notarize + DMG"
"$ROOT/scripts/release.sh" "$VERSION"

[[ -f "$DMG" ]] || { echo "!! DMG not found: $DMG" >&2; exit 1; }
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "==> sha256: $SHA"

echo "==> GitHub Release v$VERSION"
if gh release view "v$VERSION" --repo "$APP_REPO" >/dev/null 2>&1; then
    gh release upload "v$VERSION" "$DMG" --repo "$APP_REPO" --clobber
else
    gh release create "v$VERSION" "$DMG" --repo "$APP_REPO" \
        --title "ClawdDochi $VERSION" --notes "Release $VERSION"
fi

echo "==> Generate + sign Sparkle appcast"
# generate_appcast signs each update with the EdDSA private key from your
# keychain and writes appcast.xml. We point the download URL at this release's
# GitHub assets and commit appcast.xml to the app repo's main branch, which is
# where SUFeedURL (raw.githubusercontent .../main/appcast.xml) serves it from.
GENAPPCAST="$(find "$ROOT/build" -name generate_appcast -path '*artifacts*' 2>/dev/null | head -1)"
if [[ -z "$GENAPPCAST" ]]; then
    echo "!! generate_appcast not found (resolve Sparkle first). Skipping appcast." >&2
else
    ACDIR="$ROOT/build/release/appcast"
    rm -rf "$ACDIR"; mkdir -p "$ACDIR"
    cp "$DMG" "$ACDIR/"
    "$GENAPPCAST" \
        --download-url-prefix "https://github.com/sunggyeol/ClawdDochi/releases/download/v${VERSION}/" \
        "$ACDIR"
    cp "$ACDIR/appcast.xml" "$ROOT/appcast.xml"
    git -C "$ROOT" add appcast.xml
    if ! git -C "$ROOT" diff --cached --quiet; then
        git -C "$ROOT" commit -m "appcast: ClawdDochi ${VERSION}"
        git -C "$ROOT" push
    fi
fi

echo "==> Update cask"
# version + sha256 (url already references v#{version}/ClawdDochi-#{version}.dmg)
/usr/bin/sed -i '' -E "s/version \"[^\"]*\"/version \"${VERSION}\"/" "$CASK"
/usr/bin/sed -i '' -E "s/sha256 .*/sha256 \"${SHA}\"/" "$CASK"

echo "==> Push cask to tap ($TAP_REPO)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
gh repo clone "$TAP_REPO" "$TMP" -- --depth 1
mkdir -p "$TMP/Casks"
cp "$CASK" "$TMP/Casks/clawd-dochi.rb"
git -C "$TMP" add Casks/clawd-dochi.rb
if git -C "$TMP" diff --cached --quiet; then
    echo "   (cask unchanged — nothing to push)"
else
    git -C "$TMP" commit -m "clawd-dochi ${VERSION}"
    git -C "$TMP" push
fi

echo ""
echo "============================================================"
echo "Published ClawdDochi ${VERSION}"
echo "  DMG:   $DMG"
echo "  Cask:  ${TAP_REPO} (clawd-dochi ${VERSION})"
echo "  Test:  brew update && brew upgrade --cask clawd-dochi"
echo "============================================================"
