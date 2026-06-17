//
//  HookInstaller.swift
//  ClawdDochi
//
//  Registers/unregisters ClawdDochi's Claude Code hooks in ~/.claude/settings.json,
//  preserving every other hook. It only ever touches entries whose command
//  points at this app's bundled dochi-cli helper.
//
//  Registered hooks (all invoking the absolute path to the embedded helper):
//    UserPromptSubmit -> dochi-cli working
//    Notification     -> dochi-cli attention
//    Stop             -> dochi-cli done
//    SubagentStop     -> dochi-cli done
//
//  The merge/remove logic is implemented as PURE functions on the parsed JSON
//  ([String: Any]) so unknown keys and other tools' hooks round-trip untouched,
//  and so the behavior can be verified headlessly against a temp fixture
//  (see HookInstaller.selfTest). File writes are gated behind explicit user
//  confirmation in the menu action.
//

import Foundation

@MainActor
enum HookInstaller {

    /// Substring that identifies a command as ours (independent of the .app's
    /// install location).
    static let helperMarker = "Contents/Helpers/dochi-cli"

    /// The four hooks we manage: (event name, helper argument token).
    static let managedHooks: [(event: String, token: String)] = [
        ("UserPromptSubmit", "working"),
        ("Notification", "attention"),
        ("Stop", "done"),
        ("SubagentStop", "done"),
    ]

    /// Absolute path to this app's embedded helper.
    static func embeddedHelperPath() -> String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/dochi-cli")
            .path
    }

    /// Default location of Claude Code's user settings.
    static func defaultSettingsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    // MARK: - Pure transforms

    /// Return `settings` with ClawdDochi's hooks added, using `helperPath` for
    /// the command. Any pre-existing ClawdDochi entries are removed first so the
    /// operation is idempotent; all other hooks are preserved.
    static func installed(into settings: [String: Any], helperPath: String) -> [String: Any] {
        var result = removeOurEntries(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]

        for managed in managedHooks {
            var groups = hooks[managed.event] as? [[String: Any]] ?? []
            let entry: [String: Any] = [
                "matcher": "",
                "hooks": [[
                    "type": "command",
                    "command": "\(helperPath) \(managed.token)",
                ]],
            ]
            groups.append(entry)
            hooks[managed.event] = groups
        }

        result["hooks"] = hooks
        return result
    }

    /// Return `settings` with all ClawdDochi entries removed and nothing else
    /// changed.
    static func uninstalled(from settings: [String: Any]) -> [String: Any] {
        removeOurEntries(from: settings)
    }

    /// Remove every hook entry whose command references our helper, dropping any
    /// group (and any event array / the `hooks` key) left empty.
    private static func removeOurEntries(from settings: [String: Any]) -> [String: Any] {
        var result = settings
        guard var hooks = result["hooks"] as? [String: Any] else { return result }

        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }

            groups = groups.compactMap { group in
                var g = group
                if var inner = g["hooks"] as? [[String: Any]] {
                    inner.removeAll { hook in
                        (hook["command"] as? String)?.contains(helperMarker) ?? false
                    }
                    if inner.isEmpty { return nil } // whole group was ours
                    g["hooks"] = inner
                }
                return g
            }

            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = groups
            }
        }

        if hooks.isEmpty {
            result.removeValue(forKey: "hooks")
        } else {
            result["hooks"] = hooks
        }
        return result
    }

    // MARK: - File I/O

    /// Read settings JSON from `url`. Missing file => empty object.
    static func readSettings(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// Write settings JSON to `url` (pretty-printed, stable key order), creating
    /// the parent directory if needed.
    static func writeSettings(_ settings: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url)
    }

    /// True if our hooks are currently installed in the settings at `url`.
    static func isEnabled(at url: URL) -> Bool {
        guard let settings = try? readSettings(at: url),
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        for (_, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                let inner = group["hooks"] as? [[String: Any]] ?? []
                if inner.contains(where: { ($0["command"] as? String)?.contains(helperMarker) ?? false }) {
                    return true
                }
            }
        }
        return false
    }

    /// Enable integration against the real user settings. Caller is responsible
    /// for obtaining user confirmation first.
    static func enableInRealSettings() throws {
        let url = defaultSettingsURL()
        let current = try readSettings(at: url)
        let updated = installed(into: current, helperPath: embeddedHelperPath())
        try writeSettings(updated, to: url)
    }

    /// Disable integration against the real user settings.
    static func disableInRealSettings() throws {
        let url = defaultSettingsURL()
        let current = try readSettings(at: url)
        let updated = uninstalled(from: current)
        try writeSettings(updated, to: url)
    }
}
