//
//  main.swift
//  dochi-cli
//
//  Tiny bundled helper invoked by Claude Code hooks. It takes one argument —
//  `working`, `attention`, or `done` — and broadcasts it to the running
//  ClawdDochi app over local IPC, then exits immediately (it is not resident).
//
//  IPC contract: post a DistributedNotificationCenter notification whose NAME
//  encodes the state: `com.sungoh.ClawdDochi.signal.<state>`. We do NOT rely on
//  userInfo, which is dropped across processes by the distributed center.
//

import Foundation

// Shared IPC vocabulary (kept in sync with the app's SignalReceiver).
let signalPrefix = "com.sungoh.ClawdDochi.signal."
let validTokens: Set<String> = ["working", "attention", "done", "idle"]

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: dochi-cli <working|attention|done>\n".utf8))
    exit(2)
}

let token = args[1].lowercased()
guard validTokens.contains(token) else {
    FileHandle.standardError.write(
        Data("dochi-cli: unknown signal '\(token)' (expected working|attention|done)\n".utf8))
    exit(2)
}

let name = Notification.Name(signalPrefix + token)
DistributedNotificationCenter.default().postNotificationName(
    name,
    object: nil,
    userInfo: nil,
    deliverImmediately: true
)

exit(0)
