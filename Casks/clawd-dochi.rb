cask "clawd-dochi" do
  version "1.0"
  sha256 :no_check # replaced with the real DMG checksum at release time

  url "https://github.com/sunggyeol/homebrew-clawddochi/releases/download/v#{version}/ClawdDochi-#{version}.dmg"
  name "ClawdDochi"
  desc "Menu-bar + desktop hedgehog pet that reacts to Claude Code sessions"
  homepage "https://github.com/sunggyeol/ClawdDochi"

  depends_on macos: ">= :sonoma"

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
