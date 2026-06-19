cask "clawd-dochi" do
  version "1.3"
  sha256 "bc19bcac814e8a07722ce6f5faddd85a0b2c70385a2a2688d1832a560e81e229"

  url "https://github.com/sunggyeol/ClawdDochi/releases/download/v#{version}/ClawdDochi-#{version}.dmg"
  name "ClawdDochi"
  desc "Menu-bar + desktop hedgehog pet that reacts to Claude Code sessions"
  homepage "https://github.com/sunggyeol/ClawdDochi"

  depends_on macos: ">= :tahoe"

  # The app updates itself via Sparkle, so Homebrew should not flag it stale.
  auto_updates true

  app "ClawdDochi.app"

  # Expose the bundled helper on PATH so Claude Code hooks can call it directly.
  binary "#{appdir}/ClawdDochi.app/Contents/Helpers/dochi-cli"

  zap trash: [
    "~/Library/Caches/com.sungoh.ClawdDochi",
    "~/Library/Preferences/com.sungoh.ClawdDochi.plist",
    "~/Library/Saved Application State/com.sungoh.ClawdDochi.savedState",
  ]

  caveats <<~EOS
    ClawdDochi is a menu-bar agent app (no Dock icon). After launching it,
    enable Claude Code integration from its menu, or run:
      dochi-cli done
    to test the desktop hedgehog's celebration.
  EOS
end
