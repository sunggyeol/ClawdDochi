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

/// Whether Dochi reacts to Claude Code, or just lives its own life.
enum DochiDriver: String, CaseIterable, Sendable {
    case claudeCode  // gestures/animation react to Claude Code agent state
    case autonomous  // ignores Claude Code; roams on its own

    var label: String {
        switch self {
        case .claudeCode: return "Claude Code Integration"
        case .autonomous: return "Autonomous"
        }
    }
}

/// How Dochi moves around the screen.
enum MovementStyle: String, CaseIterable, Sendable {
    case edgeWalk     // walks the full screen-edge perimeter, facing travel
    case screensaver  // DVD-style: drifts fast across the screen, bounces off walls

    var label: String {
        switch self {
        case .edgeWalk:    return "Edge Walk"
        case .screensaver: return "Screensaver (Bounce)"
        }
    }
}

/// Global movement-speed multiplier.
enum DochiSpeed: String, CaseIterable, Sendable {
    case slow, normal, fast, veryFast

    var multiplier: CGFloat {
        switch self {
        case .slow:     return 0.6
        case .normal:   return 1.0
        case .fast:     return 1.7
        case .veryFast: return 2.6
        }
    }

    var label: String {
        switch self {
        case .slow:     return "Slow"
        case .normal:   return "Normal"
        case .fast:     return "Fast"
        case .veryFast: return "Very Fast"
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
        static let driver = "dochi.driver"
        static let movement = "dochi.movement"
        static let speed = "dochi.speed"
        static let customImage = "dochi.customImage"
        static let motion = "dochi.motion"
    }

    private var observers: [() -> Void] = []

    /// Register a change observer (invoked on the main actor after any change).
    func observe(_ handler: @escaping () -> Void) {
        observers.append(handler)
    }

    private func notify() { observers.forEach { $0() } }

    var size: DochiSize {
        get { DochiSize(rawValue: defaults.string(forKey: Key.size) ?? "") ?? .small }
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

    var driver: DochiDriver {
        get { DochiDriver(rawValue: defaults.string(forKey: Key.driver) ?? "") ?? .claudeCode }
        set { defaults.set(newValue.rawValue, forKey: Key.driver); notify() }
    }

    var movement: MovementStyle {
        get { MovementStyle(rawValue: defaults.string(forKey: Key.movement) ?? "") ?? .edgeWalk }
        set { defaults.set(newValue.rawValue, forKey: Key.movement); notify() }
    }

    var speed: DochiSpeed {
        get { DochiSpeed(rawValue: defaults.string(forKey: Key.speed) ?? "") ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: Key.speed); notify() }
    }

    /// Whether Dochi moves/animates. Defaults to true; the image handlers set it
    /// (on for the built-in Dochi, off for a custom image) but the user can
    /// override it from Settings.
    var motionEnabled: Bool {
        get { defaults.object(forKey: Key.motion) == nil ? true : defaults.bool(forKey: Key.motion) }
        set { defaults.set(newValue, forKey: Key.motion); notify() }
    }

    /// Path to a user-supplied PNG/SVG used in place of the procedural Dochi.
    /// nil = use the built-in hedgehog.
    var customImagePath: String? {
        get { defaults.string(forKey: Key.customImage) }
        set {
            if let v = newValue { defaults.set(v, forKey: Key.customImage) }
            else { defaults.removeObject(forKey: Key.customImage) }
            notify()
        }
    }
}
