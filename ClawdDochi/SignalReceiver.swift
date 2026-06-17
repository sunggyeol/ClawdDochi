//
//  SignalReceiver.swift
//  ClawdDochi
//
//  Observes the name-encoded DistributedNotificationCenter signals posted by
//  dochi-cli and maps them onto AppController state.
//
//  IPC contract (must match dochi-cli): notification names are
//  `com.sungoh.ClawdDochi.signal.<state>` where <state> is one of
//  working | attention | done | idle. userInfo is intentionally ignored.
//

import AppKit
import os

@MainActor
final class SignalReceiver {
    static let signalPrefix = "com.sungoh.ClawdDochi.signal."

    private static let log = Logger(subsystem: "com.sungoh.ClawdDochi", category: "ipc")

    private let appController: AppController
    /// Tokens we register for, mapped via AgentState(signalToken:).
    private let tokens = ["working", "attention", "done", "idle"]

    init(appController: AppController) {
        self.appController = appController
        let center = DistributedNotificationCenter.default()
        for token in tokens {
            center.addObserver(
                self,
                selector: #selector(handle(_:)),
                name: Notification.Name(Self.signalPrefix + token),
                object: nil
            )
        }
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func handle(_ note: Notification) {
        // Recover the state from the notification name's suffix.
        let raw = note.name.rawValue
        guard raw.hasPrefix(Self.signalPrefix) else { return }
        let token = String(raw.dropFirst(Self.signalPrefix.count))
        guard let state = AgentState(signalToken: token) else { return }
        Self.log.notice("received signal '\(token, privacy: .public)' -> \(state.rawValue, privacy: .public)")

        // Opt-in debug trace for verifying the IPC round trip without a UI.
        if let path = ProcessInfo.processInfo.environment["CLAWDDOCHI_DEBUG_LOG"] {
            let line = "received \(token) -> \(state.rawValue)\n"
            if let data = line.data(using: .utf8) {
                if let fh = FileHandle(forWritingAtPath: path) {
                    fh.seekToEndOfFile(); fh.write(data); try? fh.close()
                } else {
                    try? data.write(to: URL(fileURLWithPath: path))
                }
            }
        }

        appController.setState(state)
    }
}
