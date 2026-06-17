//
//  MenuBarSprite.swift
//  ClawdDochi
//
//  Procedural hedgehog silhouette frames for the menu-bar status item.
//  SF Symbols has no hedgehog, so we render a tiny template NSImage per frame
//  for brand consistency with the desktop Dochi. The hedgehog always "walks"
//  (legs step, body bobs) so the menu bar item is visibly alive, RunCat-style,
//  with the gait speed + extra flourish keyed to the agent state.
//
//  This is the menu-bar half of the same swappable seam as DochiSprite.
//  TODO: swap in real hedgehog sprite sheet via SKTextureAtlas / NSImage assets.
//  To replace: return pre-rendered template NSImages from an asset catalog
//  keyed by (state, frameIndex); nothing else in StatusItemController changes.
//

import AppKit

@MainActor
enum MenuBarSprite {

    /// Logical size of a menu-bar frame (points). A little wider than tall to
    /// fit the spikes on the back and the snout up front.
    static let size = NSSize(width: 22, height: 18)

    /// Per-state animation timing: (number of frames, seconds per frame).
    /// More frames => smoother walk cycle.
    static func timing(for state: AgentState) -> (frames: Int, interval: TimeInterval) {
        switch state {
        case .idle:    return (12, 0.11) // calm steady stroll (~1.3s loop)
        case .working: return (12, 0.06) // brisk trot
        case .waiting: return (8, 0.12)  // bouncy attention
        case .done:    return (8, 0.09)  // happy hops
        }
    }

    static func frames(for state: AgentState) -> [NSImage] {
        let (count, _) = timing(for: state)
        return (0..<count).map { frame(state: state, index: $0, of: count) }
    }

    /// Render one silhouette frame. `phase` in 0..<1 drives the walk cycle.
    private static func frame(state: AgentState, index: Int, of count: Int) -> NSImage {
        let phase = count <= 1 ? 0 : CGFloat(index) / CGFloat(count)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.setFill()
        NSColor.black.setStroke()

        // Motion parameters.
        var bodyBob: CGFloat = 0     // vertical bob of the whole body
        var quillBristle: CGFloat = 1
        var lean: CGFloat = 0
        var legLift: CGFloat = 1.6   // how high each step lifts
        let walk = phase             // 0..<1 around the leg cycle

        switch state {
        case .idle:
            bodyBob = abs(sin(phase * 2 * .pi)) * 0.7
            legLift = 1.4
        case .working:
            bodyBob = abs(sin(phase * 2 * .pi)) * 1.3
            legLift = 2.4
        case .waiting:
            // Stand and bounce + bristle, looking up.
            bodyBob = abs(sin(phase * 2 * .pi)) * 2.2
            quillBristle = 1 + (index % 2 == 0 ? 0.16 : 0)
            lean = (index % 2 == 0 ? 0.10 : -0.03)
            legLift = 0.6
        case .done:
            bodyBob = sin(phase * .pi) * 3.2          // a hop arc
            quillBristle = 1 + sin(phase * .pi) * 0.30 // bristle at apex
            lean = sin(phase * 2 * .pi) * 0.16
            legLift = 0.6
        }

        drawHedgehog(bodyBob: bodyBob, quillBristle: quillBristle,
                     lean: lean, walk: walk, legLift: legLift)

        // Template => macOS tints it (white on the dark menu bar, dark on light).
        image.isTemplate = true
        return image
    }

    /// Draw a right-facing hedgehog silhouette: a body ellipse with a fan of
    /// distinct triangular spikes across the top/back, a pointed snout, an ear
    /// bump, and two stepping legs.
    private static func drawHedgehog(bodyBob: CGFloat, quillBristle: CGFloat,
                                     lean: CGFloat, walk: CGFloat, legLift: CGFloat) {
        let w = size.width, h = size.height
        let cx = w / 2 - 1
        let cy = h / 2 - 0.5 + bodyBob

        let xform = NSAffineTransform()
        xform.translateX(by: cx, yBy: cy)
        xform.rotate(byRadians: lean)
        xform.translateX(by: -cx, yBy: -cy)
        xform.concat()

        let a: CGFloat = 7.0   // body half-width
        let b: CGFloat = 5.2   // body half-height

        // Spikes: a fan of triangles around the top and back (left) of the body,
        // each tilted slightly back for a swept look.
        let spikes = 9
        let arcStart: CGFloat = 28 * .pi / 180   // upper-front
        let arcEnd: CGFloat = 212 * .pi / 180     // lower-back
        for i in 0..<spikes {
            let t = CGFloat(i) / CGFloat(spikes - 1)
            let ang = arcStart + (arcEnd - arcStart) * t
            let base = NSPoint(x: cx + a * 0.92 * cos(ang), y: cy + b * 0.92 * sin(ang))
            let dir = ang + 0.32 // tilt back
            let len = (3.2 + 1.1 * sin(t * .pi)) * quillBristle
            let tip = NSPoint(x: base.x + cos(dir) * len, y: base.y + sin(dir) * len)
            let perp = dir + .pi / 2
            let hw: CGFloat = 1.5
            let p = NSBezierPath()
            p.move(to: NSPoint(x: base.x + cos(perp) * hw, y: base.y + sin(perp) * hw))
            p.line(to: tip)
            p.line(to: NSPoint(x: base.x - cos(perp) * hw, y: base.y - sin(perp) * hw))
            p.close()
            p.fill()
        }

        // Two stepping legs (drawn before the body so they tuck under it).
        let legY = cy - b + 0.5
        for (i, lx) in [CGFloat(-3.5), 2.5].enumerated() {
            let legPhase = walk * 2 * .pi + (i == 0 ? 0 : .pi)
            let lift = max(0, sin(legPhase)) * legLift
            let swing = cos(legPhase) * 1.4
            let leg = NSRect(x: cx + lx + swing - 1.1, y: legY - 2.4 + lift,
                             width: 2.2, height: 3.0)
            NSBezierPath(ovalIn: leg).fill()
        }

        // Body ellipse (face/belly mass) on top of legs and spike bases.
        NSBezierPath(ovalIn: NSRect(x: cx - a, y: cy - b, width: a * 2, height: b * 2)).fill()

        // Snout: a short wedge poking out the front-right.
        let snout = NSBezierPath()
        snout.move(to: NSPoint(x: cx + a - 0.5, y: cy - 2.2))
        snout.line(to: NSPoint(x: cx + a + 3.4, y: cy - 1.4))
        snout.line(to: NSPoint(x: cx + a - 1.0, y: cy + 1.4))
        snout.close()
        snout.fill()

        // Ear bump on the upper-front of the body.
        NSBezierPath(ovalIn: NSRect(x: cx + a - 4.4, y: cy + b - 2.2,
                                    width: 3.6, height: 3.6)).fill()

        xform.invert()
        xform.concat()
    }
}
