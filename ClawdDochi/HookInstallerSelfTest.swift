//
//  HookInstallerSelfTest.swift
//  ClawdDochi
//
//  Headless verification of HookInstaller against a TEMP fixture. Run with:
//    ClawdDochi --selftest-hooks <fixtureDir>
//  It writes a fixture settings.json containing an unrelated hook, runs
//  install + uninstall, asserts the invariants, prints the before/after JSON,
//  and terminates. It never touches the real ~/.claude/settings.json.
//

import AppKit

@MainActor
enum HookInstallerSelfTest {

    static func requestedDirectory() -> String? {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--selftest-hooks"), idx + 1 < args.count
        else { return nil }
        return args[idx + 1]
    }

    static func runAndExit(in dir: String) {
        var ok = true
        func check(_ cond: Bool, _ label: String) {
            print(cond ? "PASS  \(label)" : "FAIL  \(label)")
            if !cond { ok = false }
        }

        let dirURL = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        let url = dirURL.appendingPathComponent("settings.json")

        // Fixture with an UNRELATED pre-existing hook plus an unrelated top-level key.
        let original: [String: Any] = [
            "model": "claude-sonnet-4-6",
            "hooks": [
                "PostToolUse": [[
                    "matcher": "Edit|Write",
                    "hooks": [["type": "command", "command": "npx prettier --write"]],
                ]],
                "Stop": [[
                    "matcher": "",
                    "hooks": [["type": "command", "command": "echo other-tool-stop"]],
                ]],
            ],
        ]
        try? HookInstaller.writeSettings(original, to: url)

        let helper = "/Applications/ClawdDochi.app/Contents/Helpers/dochi-cli"

        print("=== BEFORE ===")
        printJSON(try? HookInstaller.readSettings(at: url))

        // ENABLE
        let before = (try? HookInstaller.readSettings(at: url)) ?? [:]
        let enabled = HookInstaller.installed(into: before, helperPath: helper)
        try? HookInstaller.writeSettings(enabled, to: url)

        print("\n=== AFTER ENABLE ===")
        printJSON(enabled)

        let hooks = enabled["hooks"] as? [String: Any] ?? [:]
        // Each managed event must have exactly one ClawdDochi entry.
        for managed in HookInstaller.managedHooks {
            let groups = hooks[managed.event] as? [[String: Any]] ?? []
            let ours = groups.filter { g in
                (g["hooks"] as? [[String: Any]] ?? []).contains {
                    ($0["command"] as? String)?.contains(HookInstaller.helperMarker) ?? false
                }
            }
            check(ours.count == 1, "\(managed.event): exactly one ClawdDochi hook")
            let cmd = (ours.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String
            check(cmd == "\(helper) \(managed.token)", "\(managed.event): command = '\(helper) \(managed.token)'")
        }
        // Unrelated hooks preserved.
        let postGroups = hooks["PostToolUse"] as? [[String: Any]] ?? []
        check(postGroups.count == 1, "PostToolUse (unrelated) preserved")
        let stopGroups = hooks["Stop"] as? [[String: Any]] ?? []
        let stopHasOther = stopGroups.contains { g in
            (g["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String) == "echo other-tool-stop" }
        }
        let stopHasOurs = stopGroups.contains { g in
            (g["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(HookInstaller.helperMarker) ?? false }
        }
        check(stopHasOther && stopHasOurs, "Stop keeps the other tool's hook alongside ours")
        check((enabled["model"] as? String) == "claude-sonnet-4-6", "unrelated top-level key preserved")
        check(HookInstaller.isEnabled(at: url), "isEnabled() reports true after enable")

        // Idempotency: enabling again should not duplicate.
        let twice = HookInstaller.installed(into: enabled, helperPath: helper)
        let twiceStop = (twice["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]] ?? []
        let twiceOurs = twiceStop.filter { g in
            (g["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains(HookInstaller.helperMarker) ?? false }
        }
        check(twiceOurs.count == 1, "enabling twice does not duplicate our Stop hook")

        // DISABLE -> restores original.
        let disabled = HookInstaller.uninstalled(from: enabled)
        try? HookInstaller.writeSettings(disabled, to: url)

        print("\n=== AFTER DISABLE ===")
        printJSON(disabled)

        check(!HookInstaller.isEnabled(at: url), "isEnabled() reports false after disable")
        check(jsonEqual(disabled, original), "disable restores the exact original settings")

        print("\n\(ok ? "ALL CHECKS PASSED" : "SOME CHECKS FAILED")")
        exit(ok ? 0 : 1)
    }

    private static func printJSON(_ obj: [String: Any]?) {
        guard let obj,
              let data = try? JSONSerialization.data(
                withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let s = String(data: data, encoding: .utf8) else { print("<nil>"); return }
        print(s)
    }

    private static func jsonEqual(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        guard let da = try? JSONSerialization.data(withJSONObject: a, options: [.sortedKeys]),
              let db = try? JSONSerialization.data(withJSONObject: b, options: [.sortedKeys])
        else { return false }
        return da == db
    }
}
