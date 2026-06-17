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
    private let settings = DochiSettings.shared

    private var frames: [NSImage] = []
    private var frameIndex = 0
    private var timer: Timer?

    init(appController: AppController) {
        self.appController = appController
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

        // TEMPORARY debug submenu to set each state manually.
        let debugItem = NSMenuItem(title: "Debug: Set State", action: nil, keyEquivalent: "")
        let debugMenu = NSMenu()
        for state in AgentState.allCases {
            let item = NSMenuItem(title: state.rawValue.capitalized,
                                  action: #selector(debugSetState(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = state.rawValue
            debugMenu.addItem(item)
        }
        debugItem.submenu = debugMenu
        menu.addItem(debugItem)

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

        // Claude Code hook integration. Writes are gated behind an NSAlert.
        let enabled = HookInstaller.isEnabled(at: HookInstaller.defaultSettingsURL())
        let enableItem = NSMenuItem(title: "Enable Claude Code Integration",
                                    action: #selector(enableIntegration),
                                    keyEquivalent: "")
        enableItem.target = self
        enableItem.state = enabled ? .on : .off
        menu.addItem(enableItem)

        let disableItem = NSMenuItem(title: "Disable Claude Code Integration",
                                     action: #selector(disableIntegration),
                                     keyEquivalent: "")
        disableItem.target = self
        menu.addItem(disableItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ClawdDochi",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        statusItem.menu = menu
    }

    @objc private func debugSetState(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let state = AgentState(rawValue: raw) else { return }
        appController.setState(state)
    }

    @objc private func toggleShowDochi() {
        settings.showDochi.toggle()
        buildMenu()
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

    // MARK: - Hook integration actions

    @objc private func enableIntegration() {
        let url = HookInstaller.defaultSettingsURL()
        let alert = NSAlert()
        alert.messageText = "Enable Claude Code integration?"
        alert.informativeText = """
        ClawdDochi will add four hooks to \(url.path) that run its bundled \
        helper when Claude Code starts a prompt, needs attention, or finishes. \
        Your existing hooks are preserved.
        """
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try HookInstaller.enableInRealSettings() } catch { presentError(error) }
        buildMenu()
    }

    @objc private func disableIntegration() {
        let alert = NSAlert()
        alert.messageText = "Disable Claude Code integration?"
        alert.informativeText = "ClawdDochi will remove only its own hooks, leaving all others intact."
        alert.addButton(withTitle: "Disable")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try HookInstaller.disableInRealSettings() } catch { presentError(error) }
        buildMenu()
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "ClawdDochi could not update Claude Code settings."
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
