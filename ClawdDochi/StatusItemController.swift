//
//  StatusItemController.swift
//  ClawdDochi
//
//  Owns the NSStatusItem and animates it RunCat-style: it cycles a set of
//  procedural hedgehog silhouette frames on a Timer, with a different frame set
//  and speed per AgentState. Observes AppController for state changes and hosts
//  the menu (a temporary debug submenu plus Quit).
//

import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let appController: AppController
    private let updater: UpdaterController
    private let settings = DochiSettings.shared

    private var frames: [NSImage] = []
    private var frameIndex = 0
    private var timer: Timer?

    init(appController: AppController, updater: UpdaterController) {
        self.appController = appController
        self.updater = updater
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.toolTip = "ClawdDochi"
        buildMenu()

        appController.observe { [weak self] state in
            self?.apply(state)
        }
    }

    // MARK: - Animation

    private func apply(_ state: AgentState) {
        timer?.invalidate()
        frames = MenuBarSprite.frames(for: state)
        frameIndex = 0
        statusItem.button?.toolTip = "ClawdDochi — \(state.rawValue)"
        showCurrentFrame()

        let (_, interval) = MenuBarSprite.timing(for: state)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceFrame(for: state) }
        }
        // .common so animation keeps running while menus are open.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func advanceFrame(for state: AgentState) {
        guard !frames.isEmpty else { return }
        frameIndex += 1

        // `done` is a one-shot: after a full celebratory cycle, settle to idle.
        if state == .done && frameIndex >= frames.count {
            appController.returnToIdle()
            return
        }
        frameIndex %= frames.count
        showCurrentFrame()
    }

    private func showCurrentFrame() {
        guard !frames.isEmpty else { return }
        statusItem.button?.image = frames[frameIndex]
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        // Mode: react to Claude Code, or roam autonomously.
        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for driver in DochiDriver.allCases {
            let item = NSMenuItem(title: driver.label, action: #selector(setDriver(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = driver.rawValue
            item.state = (settings.driver == driver) ? .on : .off
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        // Movement style.
        let moveItem = NSMenuItem(title: "Movement", action: nil, keyEquivalent: "")
        let moveMenu = NSMenu()
        for style in MovementStyle.allCases {
            let item = NSMenuItem(title: style.label, action: #selector(setMovement(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = (settings.movement == style) ? .on : .off
            moveMenu.addItem(item)
        }
        moveItem.submenu = moveMenu
        menu.addItem(moveItem)

        menu.addItem(.separator())

        // Show/hide the desktop pet.
        let showItem = NSMenuItem(title: "Show Dochi",
                                  action: #selector(toggleShowDochi),
                                  keyEquivalent: "")
        showItem.target = self
        showItem.state = settings.showDochi ? .on : .off
        menu.addItem(showItem)

        // Settings submenu: size, color scheme, completion animation.
        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = makeSettingsMenu()
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let updateItem = NSMenuItem(title: "Check for Updates…",
                                    action: #selector(checkForUpdates),
                                    keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClawdDochi",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        statusItem.menu = menu
    }

    @objc private func setDriver(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let v = DochiDriver(rawValue: raw) else { return }
        settings.driver = v
        // Mode also manages the Claude Code hooks in ~/.claude/settings.json,
        // so the two are never out of sync. Writes are confirmed via NSAlert.
        let url = HookInstaller.defaultSettingsURL()
        let hooksInstalled = HookInstaller.isEnabled(at: url)
        switch v {
        case .claudeCode where !hooksInstalled:
            promptInstallHooks(url: url)
        case .autonomous where hooksInstalled:
            promptRemoveHooks()
        default:
            break
        }
        buildMenu()
    }

    private func promptInstallHooks(url: URL) {
        let alert = NSAlert()
        alert.messageText = "Enable Claude Code integration?"
        alert.informativeText = """
        Dochi needs four hooks in \(url.path) so Claude Code can tell it when a \
        prompt starts, needs attention, or finishes. Your existing hooks are \
        preserved. Without them, Claude Code Integration mode has nothing to react to.
        """
        alert.addButton(withTitle: "Install Hooks")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try HookInstaller.enableInRealSettings() } catch { presentError(error) }
    }

    private func promptRemoveHooks() {
        let alert = NSAlert()
        alert.messageText = "Remove Claude Code hooks?"
        alert.informativeText = "Autonomous mode ignores Claude Code. Remove ClawdDochi's hooks from your Claude Code settings? Only ClawdDochi's entries are removed."
        alert.addButton(withTitle: "Remove Hooks")
        alert.addButton(withTitle: "Keep Them")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try HookInstaller.disableInRealSettings() } catch { presentError(error) }
    }

    @objc private func setMovement(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let v = MovementStyle(rawValue: raw) else { return }
        settings.movement = v
        buildMenu()
    }

    @objc private func toggleShowDochi() {
        settings.showDochi.toggle()
        buildMenu()
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    // MARK: - Settings menu

    private func makeSettingsMenu() -> NSMenu {
        let menu = NSMenu()

        // Size
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for size in DochiSize.allCases {
            let item = NSMenuItem(title: size.label, action: #selector(setSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            item.state = (settings.size == size) ? .on : .off
            sizeMenu.addItem(item)
        }
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        // Appearance (color scheme)
        let appItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        for appearance in DochiAppearance.allCases {
            let item = NSMenuItem(title: appearance.label, action: #selector(setAppearance(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = appearance.rawValue
            item.state = (settings.appearance == appearance) ? .on : .off
            appMenu.addItem(item)
        }
        appItem.submenu = appMenu
        menu.addItem(appItem)

        // Completion animation
        let celItem = NSMenuItem(title: "Completion Animation", action: nil, keyEquivalent: "")
        let celMenu = NSMenu()
        for style in CelebrationStyle.allCases {
            let item = NSMenuItem(title: style.label, action: #selector(setCelebration(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.state = (settings.celebration == style) ? .on : .off
            celMenu.addItem(item)
        }
        celItem.submenu = celMenu
        menu.addItem(celItem)

        return menu
    }

    @objc private func setSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let v = DochiSize(rawValue: raw) else { return }
        settings.size = v
        buildMenu()
    }

    @objc private func setAppearance(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let v = DochiAppearance(rawValue: raw) else { return }
        settings.appearance = v
        buildMenu()
    }

    @objc private func setCelebration(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let v = CelebrationStyle(rawValue: raw) else { return }
        settings.celebration = v
        // Preview the chosen animation immediately.
        appController.setState(.done)
        buildMenu()
    }

    // MARK: - Hook integration

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "ClawdDochi could not update Claude Code settings."
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
