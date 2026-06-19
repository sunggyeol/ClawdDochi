//
//  DochiSprite.swift
//  ClawdDochi
//
//  The single seam for Dochi's appearance and motion.
//
//  Dochi is a small, cute hedgehog drawn PROCEDURALLY in SpriteKit — no
//  external image assets. The whole creature is assembled as child nodes of
//  one container (`dochiNode`) so it can be moved, flipped, and animated as a
//  unit. Gestures are exposed as `SKAction`s and a `renderPose` helper renders
//  any state to a still image for previews.
//
//  TODO: swap in real hedgehog sprite sheet via SKTextureAtlas.
//  To replace the procedural art with a frame-based atlas later:
//    1. Load `SKTextureAtlas(named: "Dochi")`.
//    2. In `makeNode()`, build an `SKSpriteNode(texture:)` instead of the
//       shape children, keyed off `DochiPalette` / `DochiMetrics` only where
//       relevant.
//    3. Replace each gesture builder's shape-targeted actions with
//       `SKAction.animate(with:timePerFrame:)` over the atlas frames.
//  Nothing in PetWindowController (wandering) or AppController (state) reads
//  the internals of the node — they only call the gesture builders below — so
//  the swap stays contained to this file.
//

import SpriteKit

// MARK: - Tunable appearance parameters
//
// All of Dochi's look lives here. Tweak these to restyle the hedgehog without
// touching geometry code elsewhere.

enum DochiMetrics {
    /// Logical footprint of the creature, in points. The pet window and preview
    /// canvas are sized around this.
    static let canvasSize: CGFloat = 128

    /// Bold cartoon outline width shared by all parts.
    static let outline: CGFloat = 3.2

    // Spiky quill mass. Drawn as TWO layered zig-zag rows with slightly
    // irregular spike lengths, for an organic look distinct from a uniform
    // gear/clip-art silhouette.
    static let quillCenter = CGPoint(x: -10, y: 4)
    static let quillRadiusX: CGFloat = 47
    static let quillRadiusY: CGFloat = 41
    static let spikeCount: Int = 22          // many, evenly-sized spikes
    static let spikeOuterScale: CGFloat = 1.16 // tip radius factor (shorter => rounder)
    static let spikeInnerScale: CGFloat = 1.02 // shallow valleys => full, ball-like
    static let spikeJitter: CGFloat = 0.0      // uniform spike length
    /// Darker under-row, slightly larger and rotated half a spike.
    static let underSpikeScale: CGFloat = 1.06

    // Forehead fur tuft (a few little spikes between the face and quills).
    static let tuftBase = CGPoint(x: 14, y: 26)

    // Face blob (rounded tan mass overlapping the front-right).
    static let faceCenter = CGPoint(x: 28, y: -6)
    static let faceRadiusX: CGFloat = 33
    static let faceRadiusY: CGFloat = 31
    /// Snout tip, where the nose sits (front-right, slightly low).
    static let snoutTip = CGPoint(x: 64, y: -14)

    // Ear (rounded, on top of the face).
    static let earCenter = CGPoint(x: 34, y: 20)
    static let earRadius: CGFloat = 11

    // Eye + nose dots.
    static let eyeRadius: CGFloat = 4.6
    static let eyeOffset = CGPoint(x: 26, y: 2)
    static let noseRadius: CGFloat = 5.5

    // Feet (four little stubs along the bottom).
    static let footWidth: CGFloat = 12
    static let footHeight: CGFloat = 13
    static let footXs: [CGFloat] = [-30, -13, 16, 33]
    static let footY: CGFloat = -40
}

/// The set of fill/stroke colors used to skin Dochi. Two presets: the warm
/// terracotta `color` identity and a clean `whiteOnly` scheme.
struct DochiPalette {
    let outline, face, quill, quillDark, earInner, nose, eye, foot, cheek, freckle: NSColor

    /// Warm terracotta / coral identity (nods to Claude's brand) — deliberately
    /// distinct from a flat two-tone brown clip-art hedgehog.
    static let color = DochiPalette(
        outline:   NSColor(calibratedRed: 0.24, green: 0.14, blue: 0.11, alpha: 1),
        face:      NSColor(calibratedRed: 0.99, green: 0.93, blue: 0.81, alpha: 1),
        quill:     NSColor(calibratedRed: 0.74, green: 0.45, blue: 0.31, alpha: 1),
        quillDark: NSColor(calibratedRed: 0.55, green: 0.32, blue: 0.22, alpha: 1),
        earInner:  NSColor(calibratedRed: 0.95, green: 0.69, blue: 0.57, alpha: 1),
        nose:      NSColor(calibratedRed: 0.24, green: 0.14, blue: 0.11, alpha: 1),
        eye:       NSColor(calibratedRed: 0.20, green: 0.13, blue: 0.12, alpha: 1),
        foot:      NSColor(calibratedRed: 0.96, green: 0.87, blue: 0.74, alpha: 1),
        cheek:     NSColor(calibratedRed: 0.98, green: 0.60, blue: 0.52, alpha: 0.60),
        freckle:   NSColor(calibratedRed: 0.80, green: 0.52, blue: 0.42, alpha: 0.85))

    /// Clean white fills with the dark outline preserved; blush/freckles hidden,
    /// under-row a light gray for subtle depth.
    static let whiteOnly = DochiPalette(
        outline:   NSColor(calibratedWhite: 0.16, alpha: 1),
        face:      NSColor(calibratedWhite: 1.0, alpha: 1),
        quill:     NSColor(calibratedWhite: 1.0, alpha: 1),
        quillDark: NSColor(calibratedWhite: 0.88, alpha: 1),
        earInner:  NSColor(calibratedWhite: 0.85, alpha: 1),
        nose:      NSColor(calibratedWhite: 0.16, alpha: 1),
        eye:       NSColor(calibratedWhite: 0.16, alpha: 1),
        foot:      NSColor(calibratedWhite: 1.0, alpha: 1),
        cheek:     .clear,
        freckle:   .clear)

    static func preset(for appearance: DochiAppearance) -> DochiPalette {
        switch appearance {
        case .color:     return .color
        case .whiteOnly: return .whiteOnly
        }
    }
}

// MARK: - DochiSprite

/// Builds and animates the procedural hedgehog. One instance owns one node.
@MainActor
final class DochiSprite {

    /// The container node. Add this to a scene; move/flip/animate it as a unit.
    let node = SKNode()

    /// Child node holding all quills, so gestures can bristle them together.
    private let quillLayer = SKNode()
    private let bodyLayer = SKNode()

    /// nodeName used to find the running celebration so `done` is one-shot.
    static let celebrationKey = "dochi.celebration"
    static let idleKey = "dochi.idle"
    static let gestureKey = "dochi.gesture"

    /// Active color scheme. Set once at init; change by rebuilding the sprite.
    let palette: DochiPalette

    init(appearance: DochiAppearance = .color) {
        self.palette = DochiPalette.preset(for: appearance)
        node.name = "dochiNode"
        build()
    }

    /// Build from a user-supplied image (PNG/SVG) instead of the procedural
    /// hedgehog. The image becomes a single sprite centered at the node origin,
    /// fitted to the standard canvas size. There are no procedural feet, so the
    /// leg-walk animation is naturally skipped; all other gestures (breathing,
    /// bob, hop/spin celebration, sparkles, facing flip) still apply to the node.
    init(customImage image: NSImage) {
        self.palette = .color // unused for custom images
        node.name = "dochiNode"
        buildCustom(image)
    }

    // MARK: - Construction

    private func buildCustom(_ image: NSImage) {
        node.removeAllChildren()
        feet.removeAll()
        let sprite = SKSpriteNode(texture: SKTexture(image: image))
        let maxDim = max(image.size.width, image.size.height)
        let scale = maxDim > 0 ? DochiMetrics.canvasSize / maxDim : 1
        sprite.size = CGSize(width: image.size.width * scale,
                             height: image.size.height * scale)
        node.addChild(sprite) // SKSpriteNode is centered (anchor 0.5) at origin
    }

    private func build() {
        node.removeAllChildren()
        quillLayer.removeAllChildren()
        bodyLayer.removeAllChildren()

        // Feet sit behind everything; the spiky quill ball behind the face.
        buildFeet(into: bodyLayer)
        buildQuills(into: quillLayer)
        node.addChild(bodyLayer)   // feet
        node.addChild(quillLayer)  // spike ball
        buildFace(into: node)      // face + ear + features on top
    }

    /// Individual foot nodes, kept so the legs can animate independently of the
    /// body gesture. Each foot's resting position is (0,0); the drawn offset is
    /// baked into its path, so a leg bob just nudges `position.y`.
    private var feet: [SKShapeNode] = []

    private func buildFeet(into parent: SKNode) {
        feet.removeAll()
        for x in DochiMetrics.footXs {
            let rect = CGRect(x: x - DochiMetrics.footWidth / 2,
                              y: DochiMetrics.footY - DochiMetrics.footHeight / 2,
                              width: DochiMetrics.footWidth,
                              height: DochiMetrics.footHeight)
            let foot = SKShapeNode(path: CGPath(roundedRect: rect, cornerWidth: 5,
                                                cornerHeight: 5, transform: nil))
            foot.fillColor = palette.foot
            foot.strokeColor = palette.outline
            foot.lineWidth = DochiMetrics.outline
            parent.addChild(foot)
            feet.append(foot)
        }
    }

    /// Trot the legs: each foot bobs up/down, the pairs in opposite phase, at a
    /// speed that matches the state. Runs continuously so Dochi always looks
    /// like it's padding along.
    /// Stop the leg animation and rest the feet (used when motion is disabled).
    func stopLegs() {
        for foot in feet {
            foot.removeAction(forKey: "legs")
            foot.position = .zero
        }
    }

    func animateLegs(for state: AgentState) {
        let period: TimeInterval
        let lift: CGFloat
        switch state {
        case .working: period = 0.28; lift = 5
        case .idle:    period = 0.50; lift = 3.5  // a relaxed but visible stroll
        case .waiting: period = 0.34; lift = 4
        case .done:    period = 0.18; lift = 6     // excited little tippy-taps
        }

        for (i, foot) in feet.enumerated() {
            foot.removeAction(forKey: "legs")
            foot.position = .zero
            let up = SKAction.moveBy(x: 0, y: lift, duration: period / 2)
            let down = SKAction.moveBy(x: 0, y: -lift, duration: period / 2)
            up.timingMode = .easeOut
            down.timingMode = .easeIn
            let cycle = SKAction.repeatForever(.sequence([up, down]))
            // Alternate the two pairs by half a period for a walking gait.
            let offset = (i % 2 == 0) ? 0 : period / 2
            foot.run(.sequence([.wait(forDuration: offset), cycle]), withKey: "legs")
        }
    }

    /// The spike mass: a darker under-row plus a lighter main row, each a closed
    /// zig-zag path with slightly irregular spike lengths for an organic,
    /// non-uniform look. The main row is named "quill" so gestures bristle it.
    private func buildQuills(into parent: SKNode) {
        let c = DochiMetrics.quillCenter
        let rx = DochiMetrics.quillRadiusX
        let ry = DochiMetrics.quillRadiusY
        let spikes = DochiMetrics.spikeCount

        // Deterministic per-spike length variation (no randomness => stable art).
        func jitter(_ i: Int) -> CGFloat {
            1 + DochiMetrics.spikeJitter * sin(CGFloat(i) * 1.7 + 0.5)
        }

        func spikePath(outer: CGFloat, inner: CGFloat, phase: CGFloat) -> CGPath {
            let path = CGMutablePath()
            let pointCount = spikes * 2
            for i in 0..<pointCount {
                let angle = (CGFloat(i) / CGFloat(pointCount)) * 2 * .pi + phase
                let isTip = i % 2 == 0
                let base = isTip ? outer * jitter(i / 2) : inner
                let p = CGPoint(x: c.x + rx * base * cos(angle),
                                y: c.y + ry * base * sin(angle))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            return path
        }

        // Under-row: darker, larger, offset half a spike so its tips peek out
        // between the main spikes.
        let halfStep = (.pi) / CGFloat(spikes)
        let under = SKShapeNode(path: spikePath(
            outer: DochiMetrics.spikeOuterScale * DochiMetrics.underSpikeScale,
            inner: DochiMetrics.spikeInnerScale,
            phase: halfStep))
        under.fillColor = palette.quillDark
        under.strokeColor = palette.outline
        under.lineWidth = DochiMetrics.outline
        under.lineJoin = .round
        under.name = "quill"
        parent.addChild(under)

        // Main row on top.
        let ball = SKShapeNode(path: spikePath(
            outer: DochiMetrics.spikeOuterScale,
            inner: DochiMetrics.spikeInnerScale,
            phase: 0))
        ball.fillColor = palette.quill
        ball.strokeColor = palette.outline
        ball.lineWidth = DochiMetrics.outline
        ball.lineJoin = .round
        ball.name = "quill"
        parent.addChild(ball)

        // Forehead fur tuft: three little spikes poking up where the face meets
        // the quills — a distinctive cowlick.
        let t = DochiMetrics.tuftBase
        for (dx, h, w) in [(CGFloat(-6), CGFloat(16), CGFloat(4)),
                           (CGFloat(2), CGFloat(20), CGFloat(4.5)),
                           (CGFloat(10), CGFloat(15), CGFloat(4))] {
            let tuft = CGMutablePath()
            tuft.move(to: CGPoint(x: t.x + dx - w, y: t.y))
            tuft.addLine(to: CGPoint(x: t.x + dx - 1, y: t.y + h))   // leans back-left
            tuft.addLine(to: CGPoint(x: t.x + dx + w, y: t.y))
            tuft.closeSubpath()
            let node = SKShapeNode(path: tuft)
            node.fillColor = palette.quill
            node.strokeColor = palette.outline
            node.lineWidth = DochiMetrics.outline * 0.7
            node.lineJoin = .round
            parent.addChild(node)
        }
    }

    /// The tan face blob (with a pointed snout), the ear, and the face features.
    private func buildFace(into parent: SKNode) {
        let f = DochiMetrics.faceCenter
        let rx = DochiMetrics.faceRadiusX
        let ry = DochiMetrics.faceRadiusY

        // Ear (behind the face edge): outer + inner.
        let ear = SKShapeNode(circleOfRadius: DochiMetrics.earRadius)
        ear.fillColor = palette.face
        ear.strokeColor = palette.outline
        ear.lineWidth = DochiMetrics.outline
        ear.position = DochiMetrics.earCenter
        parent.addChild(ear)
        let earInner = SKShapeNode(circleOfRadius: DochiMetrics.earRadius * 0.55)
        earInner.fillColor = palette.earInner
        earInner.strokeColor = .clear
        earInner.position = DochiMetrics.earCenter
        parent.addChild(earInner)

        // Face blob: a smooth rounded shape that tapers to the snout tip.
        let tip = DochiMetrics.snoutTip
        let face = CGMutablePath()
        // Build an ellipse-like blob via cubic curves, pulling the lower-right
        // toward the snout tip for a pointed nose.
        let top    = CGPoint(x: f.x, y: f.y + ry)
        let left   = CGPoint(x: f.x - rx, y: f.y)
        let bottom = CGPoint(x: f.x, y: f.y - ry)
        face.move(to: top)
        face.addCurve(to: left,   control1: CGPoint(x: f.x - rx * 0.9, y: f.y + ry),
                                   control2: CGPoint(x: f.x - rx, y: f.y + ry * 0.7))
        face.addCurve(to: bottom, control1: CGPoint(x: f.x - rx, y: f.y - ry * 0.7),
                                   control2: CGPoint(x: f.x - rx * 0.55, y: f.y - ry))
        face.addCurve(to: tip,    control1: CGPoint(x: f.x + rx * 0.45, y: f.y - ry),
                                   control2: CGPoint(x: tip.x - 6, y: tip.y - 6))
        face.addCurve(to: top,    control1: CGPoint(x: tip.x + 2, y: tip.y + 18),
                                   control2: CGPoint(x: f.x + rx * 0.7, y: f.y + ry))
        let faceNode = SKShapeNode(path: face)
        faceNode.fillColor = palette.face
        faceNode.strokeColor = palette.outline
        faceNode.lineWidth = DochiMetrics.outline
        faceNode.lineJoin = .round
        parent.addChild(faceNode)

        // Cheek blush.
        let cheek = SKShapeNode(ellipseOf: CGSize(width: 13, height: 9))
        cheek.fillColor = palette.cheek
        cheek.strokeColor = .clear
        cheek.position = CGPoint(x: 34, y: -6)
        parent.addChild(cheek)

        // Three little freckles on the cheek — a distinctive marking.
        for fp in [CGPoint(x: 30, y: -3), CGPoint(x: 36, y: -2), CGPoint(x: 33, y: -8)] {
            let freckle = SKShapeNode(circleOfRadius: 1.3)
            freckle.fillColor = palette.freckle
            freckle.strokeColor = .clear
            freckle.position = fp
            parent.addChild(freckle)
        }

        // Nose at the snout tip.
        let nose = SKShapeNode(circleOfRadius: DochiMetrics.noseRadius)
        nose.fillColor = palette.nose
        nose.strokeColor = .clear
        nose.position = CGPoint(x: tip.x - 2, y: tip.y + 2)
        parent.addChild(nose)

        // Smile: a small downward arc just behind/below the nose.
        let smile = CGMutablePath()
        smile.move(to: CGPoint(x: tip.x - 10, y: tip.y - 2))
        smile.addQuadCurve(to: CGPoint(x: tip.x - 22, y: tip.y - 4),
                           control: CGPoint(x: tip.x - 16, y: tip.y - 9))
        let smileNode = SKShapeNode(path: smile)
        smileNode.strokeColor = palette.outline
        smileNode.lineWidth = 2.0
        smileNode.lineCap = .round
        smileNode.fillColor = .clear
        parent.addChild(smileNode)

        // Eye (single dot) with a tiny highlight.
        let eye = SKShapeNode(circleOfRadius: DochiMetrics.eyeRadius)
        eye.fillColor = palette.eye
        eye.strokeColor = .clear
        eye.position = DochiMetrics.eyeOffset
        parent.addChild(eye)
        let glint = SKShapeNode(circleOfRadius: DochiMetrics.eyeRadius * 0.35)
        glint.fillColor = .white
        glint.strokeColor = .clear
        glint.position = CGPoint(x: DochiMetrics.eyeOffset.x + 1.4,
                                 y: DochiMetrics.eyeOffset.y + 1.4)
        parent.addChild(glint)
    }

    // MARK: - Facing

    /// Face the given travel direction by flipping the whole node horizontally.
    func face(_ dx: CGFloat) {
        guard abs(dx) > 0.01 else { return }
        node.xScale = dx < 0 ? -abs(node.xScale) : abs(node.xScale)
    }

    // MARK: - Gestures (state behaviors)
    //
    // Each returns an SKAction to run on `node`. PetWindowController drives
    // these; it never touches the node internals.

    /// idle: slow breathing squash-stretch, loops forever.
    func idleAction() -> SKAction {
        let inhale = SKAction.scaleX(to: 1.0, y: 1.05, duration: 1.4)
        let exhale = SKAction.scaleX(to: 1.04, y: 0.97, duration: 1.4)
        inhale.timingMode = .easeInEaseOut
        exhale.timingMode = .easeInEaseOut
        return .repeatForever(.sequence([inhale, exhale]))
    }

    /// working: calm continuous bob, as if padding along an edge.
    func workingAction() -> SKAction {
        let up = SKAction.moveBy(x: 0, y: 4, duration: 0.45)
        let down = SKAction.moveBy(x: 0, y: -4, duration: 0.45)
        up.timingMode = .easeInEaseOut
        down.timingMode = .easeInEaseOut
        let tilt1 = SKAction.rotate(toAngle: 0.04, duration: 0.45)
        let tilt2 = SKAction.rotate(toAngle: -0.04, duration: 0.45)
        return .repeatForever(.sequence([
            .group([up, tilt1]),
            .group([down, tilt2])
        ]))
    }

    /// waiting: brief attention gesture — small hop + wiggle, loops gently.
    func waitingAction() -> SKAction {
        let hopUp = SKAction.moveBy(x: 0, y: 10, duration: 0.18)
        let hopDown = SKAction.moveBy(x: 0, y: -10, duration: 0.18)
        hopUp.timingMode = .easeOut
        hopDown.timingMode = .easeIn
        let wiggleR = SKAction.rotate(toAngle: 0.12, duration: 0.1)
        let wiggleL = SKAction.rotate(toAngle: -0.12, duration: 0.1)
        let center = SKAction.rotate(toAngle: 0, duration: 0.1)
        let pause = SKAction.wait(forDuration: 0.8)
        return .repeatForever(.sequence([
            hopUp, hopDown, wiggleR, wiggleL, center, pause
        ]))
    }

    /// done: ONE-SHOT celebration — an excited multi-beat routine, then runs
    /// `then` (settle to idle). Not repeating.
    ///
    /// Beats: anticipation wiggle → big spinning leap with a burst of star
    /// sparkles + bristling quills → bouncy landing → two happy little hops →
    /// settle. All procedural, no assets, no sound.
    func celebrationAction(style: CelebrationStyle,
                           then settle: @escaping () -> Void) -> SKAction {
        // Reusable beats.
        let wiggle = SKAction.sequence([
            SKAction.rotate(toAngle:  0.14, duration: 0.07),
            SKAction.rotate(toAngle: -0.14, duration: 0.09),
            SKAction.rotate(toAngle:  0.0,  duration: 0.06),
        ])
        let crouch = SKAction.scaleX(to: 1.14, y: 0.82, duration: 0.10)
        crouch.timingMode = .easeOut
        let bristle = SKAction.run { [weak self] in self?.bristleQuills() }
        let sparkle = SKAction.run { [weak self] in self?.emitSparkles() }
        func leap(height: CGFloat, spins: CGFloat, dur: TimeInterval) -> SKAction {
            let up = SKAction.group([
                SKAction.moveBy(x: 0, y: height, duration: dur),
                SKAction.scaleX(to: 0.9, y: 1.16, duration: dur),
                SKAction.rotate(byAngle: .pi * 2 * spins, duration: dur),
            ]); up.timingMode = .easeOut
            return up
        }
        func land(height: CGFloat, dur: TimeInterval) -> SKAction {
            let d = SKAction.group([
                SKAction.moveBy(x: 0, y: -height, duration: dur),
                SKAction.scaleX(to: 1.0, y: 1.0, duration: dur),
            ]); d.timingMode = .easeIn
            return d
        }
        let squash = SKAction.sequence([
            SKAction.scaleX(to: 1.18, y: 0.84, duration: 0.08),
            SKAction.scaleX(to: 1.0,  y: 1.0,  duration: 0.12),
        ])
        let hop = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 14, duration: 0.14),
            SKAction.moveBy(x: 0, y: -14, duration: 0.14),
            SKAction.wait(forDuration: 0.05),
        ]); hop.timingMode = .easeOut
        let settleRun = SKAction.run(settle)

        switch style {
        case .jumpSpin:
            return .sequence([wiggle, crouch, bristle, sparkle,
                              leap(height: 46, spins: 2, dur: 0.40),
                              land(height: 46, dur: 0.30), squash, hop, hop, settleRun])

        case .sparkleParty:
            // Stays grounded: bristle + repeated sparkle bursts while wiggling.
            let party = SKAction.sequence([
                sparkle, wiggle, hop, sparkle, wiggle, hop, sparkle, wiggle,
            ])
            return .sequence([bristle, party, settleRun])

        case .happyHops:
            // A flurry of bouncy hops, no spin, no sparkles.
            let bigHop = SKAction.sequence([
                SKAction.group([SKAction.moveBy(x: 0, y: 26, duration: 0.18),
                                SKAction.scaleX(to: 0.92, y: 1.12, duration: 0.18)]),
                SKAction.group([SKAction.moveBy(x: 0, y: -26, duration: 0.16),
                                SKAction.scaleX(to: 1.0, y: 1.0, duration: 0.16)]),
                squash,
            ])
            return .sequence([crouch, bigHop, bigHop, hop, hop, settleRun])

        case .backflip:
            // One big backward spin, no sparkles.
            return .sequence([wiggle, crouch, bristle,
                              leap(height: 54, spins: -1, dur: 0.5),
                              land(height: 54, dur: 0.32), squash, settleRun])
        }
    }

    /// Pop a ring of little star sparkles out from Dochi, each rising, spinning,
    /// and fading before removing itself. Purely procedural.
    private func emitSparkles() {
        let count = 9
        // Always festive, independent of the body palette.
        let colors: [NSColor] = [.systemPink, .systemYellow, .systemTeal, .systemOrange]
        for i in 0..<count {
            let star = SKShapeNode(path: Self.starPath(radius: CGFloat.random(in: 5...8)))
            star.fillColor = colors[i % colors.count].withAlphaComponent(0.95)
            star.strokeColor = palette.outline
            star.lineWidth = 1
            star.position = CGPoint(x: 0, y: 18)
            star.zPosition = 50
            node.addChild(star)

            let angle = CGFloat(i) / CGFloat(count) * 2 * .pi
            let dist = CGFloat.random(in: 42...64)
            let target = CGPoint(x: cos(angle) * dist, y: 18 + sin(angle) * dist + 14)
            let fly = SKAction.move(to: target, duration: 0.55)
            fly.timingMode = .easeOut
            let spin = SKAction.rotate(byAngle: .pi * 2, duration: 0.55)
            let fade = SKAction.sequence([
                SKAction.wait(forDuration: 0.3),
                SKAction.fadeOut(withDuration: 0.25),
            ])
            let grow = SKAction.sequence([
                SKAction.scale(to: 1.3, duration: 0.2),
                SKAction.scale(to: 0.6, duration: 0.35),
            ])
            star.run(.sequence([
                .group([fly, spin, fade, grow]),
                .removeFromParent(),
            ]))
        }
    }

    /// Build a 5-pointed star path of the given outer radius.
    private static func starPath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let points = 5
        let inner = radius * 0.42
        for i in 0..<(points * 2) {
            let r = i % 2 == 0 ? radius : inner
            let a = -CGFloat.pi / 2 + CGFloat(i) / CGFloat(points * 2) * 2 * .pi
            let p = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }

    /// Briefly splay the quills outward then relax them (used during celebration).
    private func bristleQuills() {
        for child in quillLayer.children where child.name == "quill" {
            child.removeAllActions()
            let out = SKAction.scale(to: 1.35, duration: 0.18)
            let back = SKAction.scale(to: 1.0, duration: 0.5)
            out.timingMode = .easeOut
            back.timingMode = .easeIn
            child.run(.sequence([out, back]))
        }
    }

    // MARK: - Static pose (for preview export)

    /// Apply a representative still pose for `state` to the node, mutating it in
    /// place. Used by the preview exporter so each state's PNG visibly differs.
    func applyStaticPose(_ state: AgentState) {
        node.removeAllActions()
        // Reset transform.
        node.setScale(1)
        node.xScale = abs(node.xScale)
        node.zRotation = 0
        for child in quillLayer.children where child.name == "quill" {
            child.removeAllActions(); child.setScale(1)
        }

        switch state {
        case .idle:
            node.yScale = 1.02 // gentle breathing peak
        case .working:
            node.zRotation = 0.05 // mid-stride tilt
            node.position.y += 3
        case .waiting:
            node.zRotation = -0.12 // wiggle, leaning to look up
            node.yScale = 1.04
        case .done:
            // Celebration peak: airborne, spun a little, quills bristled.
            node.zRotation = 0.5
            node.xScale = abs(node.xScale) * 0.94
            node.yScale = 1.12
            for child in quillLayer.children where child.name == "quill" {
                child.setScale(1.35)
            }
        }
    }
}
