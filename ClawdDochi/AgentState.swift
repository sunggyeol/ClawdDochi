//
//  AgentState.swift
//  ClawdDochi
//
//  The single vocabulary describing what the Claude Code agent is doing.
//  Both visible surfaces (menu-bar status item and Dochi) are driven from
//  this enum via AppController.
//

import Foundation

enum AgentState: String, CaseIterable, Sendable {
    case idle      // no active session; Dochi rests/drifts
    case working   // agent is running; Dochi paces calmly
    case waiting   // agent needs attention; brief attention gesture
    case done      // agent just finished; one-shot celebration, then idle

    /// Maps a raw IPC signal token to a state. The CLI sends `working` /
    /// `attention` / `done`; `attention` surfaces as `.waiting`.
    init?(signalToken token: String) {
        switch token {
        case "working":   self = .working
        case "attention": self = .waiting
        case "done":      self = .done
        case "idle":      self = .idle
        default:          return nil
        }
    }
}
