//
//  ClawdDochiApp.swift
//  ClawdDochi
//
//  Entry point for the ClawdDochi agent app.
//
//  This app intentionally exposes NO main window. The SwiftUI `App` body is a
//  `Settings { EmptyView() }` scene, which never auto-opens. All visible
//  surfaces — the menu-bar status item and Dochi's floating window — are
//  created imperatively in `AppDelegate`. Combined with `LSUIElement=YES`,
//  this yields a Dock-less, window-less agent app.
//

import SwiftUI

@main
struct ClawdDochiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
