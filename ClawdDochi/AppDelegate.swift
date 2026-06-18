//
//  AppDelegate.swift
//  ClawdDochi
//
//  Owns the app's imperative AppKit surfaces and the shared AppController that
//  drives them. Creates the animated menu-bar status item and the Dochi pet
//  window. (IPC signal receiver and hook integration arrive in later phases.)
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appController = AppController()
    private var statusItemController: StatusItemController?
    private var petWindow: PetWindowController?
    private var signalReceiver: SignalReceiver?
    private let updater = UpdaterController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Headless path: render preview PNGs and exit without any UI.
        if let dir = PreviewExporter.requestedDirectory() {
            PreviewExporter.runAndExit(to: dir)
            return
        }

        // Headless path: render the app icon and exit.
        if let path = PreviewExporter.requestedIconPath() {
            PreviewExporter.renderIconAndExit(to: path)
            return
        }

        // Headless path: verify HookInstaller against a temp fixture and exit.
        if let dir = HookInstallerSelfTest.requestedDirectory() {
            HookInstallerSelfTest.runAndExit(in: dir)
            return
        }

        // As an LSUIElement app we have no Dock icon and no main window;
        // `.accessory` keeps us out of the Dock and the app switcher.
        NSApp.setActivationPolicy(.accessory)

        statusItemController = StatusItemController(appController: appController, updater: updater)

        let pet = PetWindowController()
        pet.attach(to: appController)
        pet.show()
        petWindow = pet

        // Listen for IPC signals from the bundled dochi-cli helper.
        signalReceiver = SignalReceiver(appController: appController)
    }
}
