//
//  DochiSettings.swift
//  ClawdDochi
//
//  User-configurable preferences for Dochi, persisted in UserDefaults and
//  exposed through the menu-bar Settings submenu. Observers are notified
//  whenever a value changes so the surfaces can rebuild/re-skin live.
//

import Foundation
import CoreGraphics

/// Desktop pet size.
enum DochiSize: String, CaseIterable, Sendable {
    case small, medium, large

    var scale: CGFloat {
        switch self {
        case .small:  return 0.7
        case .medium: return 1.0
        case .large:  return 1.4
        }
    }

    var label: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        }
    }
}

/// Color scheme for Dochi.
enum DochiAppearance: String, CaseIterable, Sendable {
    case color      // full warm terracotta palette
    case whiteOnly  // clean white fills with the dark outline

    var label: String {
        switch self {
        case .color:     return "Color"
        case .whiteOnly: return "White Only"
        }
    }
}

/// Which one-shot routine Dochi plays when Claude Code finishes.
enum CelebrationStyle: String, CaseIterable, Sendable {
    case jumpSpin     // spinning leap + sparkles + hops (the lively default)
    case sparkleParty // stays put, wiggles, big sparkle ring
    case happyHops    // several quick bounces, no spin
    case backflip     // a single big spinning leap, no sparkles

    var label: String {
        switch self {
        case .jumpSpin:     return "Jump & Spin"
        case .sparkleParty: return "Sparkle Party"
        case .happyHops:    return "Happy Hops"
        case .backflip:     return "Backflip"
        }
    }
}

@MainActor
final class DochiSettings {
    static let shared = DochiSettings()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let size = "dochi.size"
        static let appearance = "dochi.appearance"
        static let celebration = "dochi.celebration"
        static let show = "dochi.show"
    }

    private var observers: [() -> Void] = []

    /// Register a change observer (invoked on the main actor after any change).
    func observe(_ handler: @escaping () -> Void) {
        observers.append(handler)
    }

    private func notify() { observers.forEach { $0() } }

    var size: DochiSize {
        get { DochiSize(rawValue: defaults.string(forKey: Key.size) ?? "") ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: Key.size); notify() }
    }

    var appearance: DochiAppearance {
        get { DochiAppearance(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .color }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance); notify() }
    }

    var celebration: CelebrationStyle {
        get { CelebrationStyle(rawValue: defaults.string(forKey: Key.celebration) ?? "") ?? .jumpSpin }
        set { defaults.set(newValue.rawValue, forKey: Key.celebration); notify() }
    }

    /// Whether the desktop pet is shown. Defaults to true.
    var showDochi: Bool {
        get { defaults.object(forKey: Key.show) == nil ? true : defaults.bool(forKey: Key.show) }
        set { defaults.set(newValue, forKey: Key.show); notify() }
    }
}
