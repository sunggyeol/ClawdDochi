//
//  AppController.swift
//  ClawdDochi
//
//  The single source of truth for agent state. Both visible surfaces — the
//  menu-bar status item and Dochi — observe this controller and react to
//  state changes. IPC signals (Phase 4) and the debug menu both funnel through
//  `setState`.
//

import Foundation

@MainActor
final class AppController {
    /// Current agent state. Setting it notifies all observers.
    private(set) var state: AgentState = .idle

    /// Observers invoked (on the main actor) whenever the state changes.
    private var observers: [(AgentState) -> Void] = []

    /// Register an observer. It is immediately invoked with the current state
    /// so newly attached surfaces sync up.
    func observe(_ handler: @escaping (AgentState) -> Void) {
        observers.append(handler)
        handler(state)
    }

    /// Update the current state and notify observers. `done` is a transient
    /// celebration: surfaces play their one-shot and are responsible for
    /// settling back to idle via `returnToIdle`.
    func setState(_ newState: AgentState) {
        state = newState
        for observer in observers { observer(newState) }
    }

    /// Called by a surface after a one-shot `done` celebration completes, to
    /// return the shared state to idle (so all surfaces settle together).
    func returnToIdle() {
        guard state == .done else { return }
        setState(.idle)
    }
}
