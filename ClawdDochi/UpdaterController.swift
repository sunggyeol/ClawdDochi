//
//  UpdaterController.swift
//  ClawdDochi
//
//  Wraps Sparkle's standard updater so ClawdDochi can auto-update itself for
//  users who installed it via the Homebrew cask. Sparkle checks the signed
//  appcast feed (SUFeedURL in Info.plist), and updates are verified against the
//  EdDSA public key (SUPublicEDKey). Automatic background checks are on
//  (SUEnableAutomaticChecks); this also exposes a manual "Check for Updates…".
//

import AppKit
import Sparkle

@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController

    init() {
        // startingUpdater: true → begins scheduled background checks immediately.
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        // Check once a day.
        controller.updater.updateCheckInterval = 86_400
    }

    /// User-initiated check (wired to the menu item).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    var canCheckForUpdates: Bool {
        controller.updater.canCheckForUpdates
    }
}
