# ClawdDochi — Homebrew tap

ClawdDochi is distributed as a Homebrew cask from its own tap.

## Install

```sh
brew tap sunggyeol/clawddochi
brew install --cask clawd-dochi
```

Then launch **ClawdDochi** (it appears in the menu bar — no Dock icon) and choose
**Enable Claude Code Integration** from its menu.

## Tap layout

This tap repo (`homebrew-clawddochi`) contains:

```
Casks/clawd-dochi.rb
```

The cask installs `ClawdDochi.app` and symlinks the bundled `dochi-cli` helper
onto your `PATH` (via the `binary` stanza) so Claude Code hooks can invoke it.

## Release checklist (maintainer)

1. `scripts/build-release.sh` — archive + export a Developer-ID-signed app
   (requires a *Developer ID Application* certificate).
2. `scripts/notarize.sh <app>` — submit to Apple, staple, verify with `spctl`.
3. `scripts/make-dmg.sh <app>` — build `ClawdDochi-<version>.dmg`.
4. Upload the DMG to a GitHub Release tagged `v<version>`.
5. Update `Casks/clawd-dochi.rb`: bump `version` and replace `sha256 :no_check`
   with `shasum -a 256 ClawdDochi-<version>.dmg`.

> Signing/notarization (steps 1–2) need a Developer ID Application certificate
> that is **not yet installed**, so they are scaffolded but not run.
