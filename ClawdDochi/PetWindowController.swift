//
//  PetWindowController.swift
//  ClawdDochi
//
//  Owns the transparent, borderless, click-through window that hosts Dochi.
//  The window is just large enough for the creature (~128×128) and is
//  repositioned around the screen edges to make Dochi "wander" — it is NOT a
//  full-screen overlay (a full-screen transparent overlay triggers a known
//  macOS mouse-event-capture bug that can block clicks to other apps).
//
//  Dochi wanders by walking the window's origin around the screen-edge
//  perimeter (parametrized by a single "distance traveled" scalar), flipping to
//  face the travel direction. Per-state gestures play on dochiNode inside the
//  moving window.
//

import AppKit
import SpriteKit

@MainActor
final class PetWindowController: NSObject {
    private let window: NSWindow
    private let skView: SKView
    private let scene: SKScene
    /// Scaled by the user's size preference; hosts dochi.node so gestures (which
    /// manipulate dochi.node directly) compose with the size scale.
    private let scaleContainer = SKNode()
    private(set) var dochi: DochiSprite

    private let settings: DochiSettings

    /// Window content size, computed from Dochi's rendered bounds × size scale
    /// plus margins and gesture headroom (set in layout()).
    private var windowSize = NSSize(width: DochiMetrics.canvasSize,
                                    height: DochiMetrics.canvasSize)
    /// Resting position of dochiNode within the container (gestures return here).
    private var baseNodePosition: CGPoint = .zero
    /// Effective state currently animating (idle in Autonomous mode).
    private var currentState: AgentState = .idle
    /// Raw Claude Code state last received (so toggling Mode re-evaluates).
    private var rawState: AgentState = .idle

    // Screensaver bounce state.
    private var ssCenter: CGPoint = .zero
    private var ssVel: CGPoint = CGPoint(x: 0.82, y: 0.57)
    /// Screensaver moves faster than edge-walking (× the wander speed).
    private static let screensaverSpeedFactor: CGFloat = 1.56

    // MARK: - Wandering state

    /// Distance (points) traveled along the screen-edge perimeter.
    private var pathProgress: CGFloat = 0
    /// Current wander speed in points/sec (depends on state).
    private var wanderSpeed: CGFloat = 0
    private var wanderTimer: Timer?
    private var lastTick: TimeInterval = 0
    /// Travel direction around the perimeter: +1 clockwise-ish, -1 reversed.
    private var travelDir: CGFloat = 1
    /// Remaining distance before randomly reversing direction.
    private var distanceUntilReverse: CGFloat = 1200
    /// Half the creature's height (scaled) — how far its feet reach from the
    /// window center, used to hug the screen edge closely while staying visible.
    private var creatureReach: CGFloat = 64

    /// Edge-walk speed per state. `waiting`/`done` stay put so the gesture reads.
    private func speed(for state: AgentState) -> CGFloat {
        let base: CGFloat
        switch state {
        case .idle:    base = 28   // roams around when Claude is done/idle
        case .working: base = 42   // brisk pacing while busy
        case .waiting: base = 18   // keeps moving while waiting (never frozen)
        case .done:    base = 0    // briefly holds for the celebration, then idle
        }
        return base * settings.speed.multiplier
    }

    init(settings: DochiSettings = .shared) {
        self.settings = settings
        self.dochi = DochiSprite(appearance: settings.appearance)

        let initial = NSRect(x: 0, y: 0,
                             width: DochiMetrics.canvasSize, height: DochiMetrics.canvasSize)
        window = NSWindow(contentRect: initial,
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)

        // Exact configuration required by the spec.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar              // floats above normal windows
        window.ignoresMouseEvents = true       // click-through; never steal clicks
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        skView = SKView(frame: initial)
        skView.allowsTransparency = true
        skView.ignoresSiblingOrder = true

        scene = SKScene(size: initial.size)
        super.init()

        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        scene.addChild(scaleContainer)
        scaleContainer.addChild(dochi.node)

        skView.presentScene(scene)
        window.contentView = skView

        layout()

        // Keep Dochi visible across desktop/Space switches: .canJoinAllSpaces
        // shows it everywhere, but after a Space change (especially to/from a
        // full-screen app) the borderless window can drop behind — so re-assert
        // it to the front whenever the active Space changes.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func activeSpaceChanged() {
        guard settings.showDochi else { return }
        window.orderFrontRegardless()
    }

    /// Square window sized from Dochi's diagonal (so it never clips at any
    /// rotation) plus headroom for the celebration hop. The creature is centered
    /// so the container can rotate it about its own center to face travel.
    private func layout() {
        let s = settings.size.scale
        let art = dochi.node.calculateAccumulatedFrame() // unscaled bounds
        let diagonal = hypot(art.width, art.height)
        let headroom: CGFloat = 60          // hop/bristle slack
        let side = (diagonal + headroom) * s
        windowSize = NSSize(width: side, height: side)
        // Feet reach from the creature's center toward whichever edge it walks —
        // lets the window hang off-screen so Dochi hugs the edge while staying
        // fully visible.
        creatureReach = (art.height / 2) * s

        scaleContainer.setScale(s)
        scaleContainer.position = CGPoint(x: side / 2, y: side / 2)
        // Center the art at the container origin so rotation pivots about the
        // creature's center.
        dochi.node.position = CGPoint(x: -art.midX, y: -art.midY)
        baseNodePosition = dochi.node.position

        window.setContentSize(windowSize)
        scene.size = windowSize
        skView.frame = NSRect(origin: .zero, size: windowSize)
    }

    /// Rebuild Dochi with the current appearance and re-layout (for live restyle
    /// from the Settings menu), then re-apply the current gesture.
    func applySettings() {
        dochi.node.removeFromParent()
        dochi = DochiSprite(appearance: settings.appearance)
        scaleContainer.addChild(dochi.node)
        layout()
        resetMovementState()
        applyGesture(rawState)   // re-evaluate driver (Claude vs autonomous)
        applyVisibility()
    }

    /// (Re)initialize the wander/bounce state — call on show and on any
    /// movement/size change so the new style starts cleanly without jumps.
    private func resetMovementState() {
        travelDir = 1
        pathProgress = perimeterLength() * 0.15
        distanceUntilReverse = perimeterLength() * CGFloat(Int.random(in: 1...2))

        let r = centerRect()
        let fx = min(max(window.frame.midX, r.minX), r.maxX)
        let fy = min(max(window.frame.midY, r.minY), r.maxY)
        ssCenter = NSPoint(x: fx, y: fy)
        let ang = CGFloat.random(in: 0.45...1.0)   // ~26–57° diagonal
        ssVel = NSPoint(x: cos(ang) * (Bool.random() ? 1 : -1),
                        y: sin(ang) * (Bool.random() ? 1 : -1))
    }

    /// Show or hide the pet window per the user's setting.
    private func applyVisibility() {
        if settings.showDochi {
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    private weak var appController: AppController?

    /// Observe shared state and switch Dochi's gesture accordingly.
    func attach(to controller: AppController) {
        appController = controller
        controller.observe { [weak self] state in
            self?.applyGesture(state)
        }
        settings.observe { [weak self] in
            self?.applySettings()
        }
    }

    /// Run the gesture animation for `state` on the Dochi node. In Autonomous
    /// mode, Dochi ignores Claude Code's state and just behaves as idle (roams).
    func applyGesture(_ state: AgentState) {
        rawState = state
        let effective: AgentState = (settings.driver == .autonomous) ? .idle : state
        currentState = effective
        let node = dochi.node
        node.removeAction(forKey: DochiSprite.idleKey)
        node.removeAction(forKey: DochiSprite.gestureKey)
        node.removeAllActions()
        node.setScale(1); node.zRotation = 0
        node.position = baseNodePosition   // recover from any interrupted hop

        // Legs animate independently of the body gesture.
        dochi.animateLegs(for: effective)

        wanderSpeed = speed(for: effective)

        // Stationary states stand upright so the gesture reads cleanly; moving
        // states let stepWander rotate the body to face travel.
        if wanderSpeed == 0 {
            scaleContainer.zRotation = 0
            scaleContainer.xScale = settings.size.scale
            scaleContainer.yScale = settings.size.scale
        }

        switch effective {
        case .idle:
            node.run(dochi.idleAction(), withKey: DochiSprite.idleKey)
        case .working:
            node.run(dochi.workingAction(), withKey: DochiSprite.gestureKey)
        case .waiting:
            node.run(dochi.waitingAction(), withKey: DochiSprite.gestureKey)
        case .done:
            let celebrate = dochi.celebrationAction(style: settings.celebration,
                                                    then: { [weak self] in
                self?.appController?.returnToIdle()
            })
            node.run(celebrate, withKey: DochiSprite.celebrationKey)
            // Failsafe: no matter what, never stay stuck in `done` — force a
            // return to idle (which wanders) a few seconds later. returnToIdle
            // is a no-op if we already left `done`.
            node.run(.sequence([.wait(forDuration: 4.0),
                                .run { [weak self] in self?.appController?.returnToIdle() }]),
                     withKey: "dochi.doneFailsafe")
        }
    }

    /// Show the window and start the wandering loop.
    func show() {
        resetMovementState()
        window.setFrameOrigin(origin(forCenter: pathPoint(pathProgress).center))
        applyVisibility()
        startWandering()
    }

    // MARK: - Wander engine

    private func startWandering() {
        wanderTimer?.invalidate()
        lastTick = Date().timeIntervalSinceReferenceDate
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepWander() }
        }
        RunLoop.main.add(t, forMode: .common)
        wanderTimer = t
    }

    private func stepWander() {
        let now = Date().timeIntervalSinceReferenceDate
        let dt = min(now - lastTick, 0.1) // clamp after stalls
        lastTick = now
        guard wanderSpeed > 0 else { return }
        let step = wanderSpeed * CGFloat(dt)

        switch settings.movement {
        case .edgeWalk:    stepPerimeter(step: step, dt: dt)
        case .screensaver: stepScreensaver(step: step, dt: dt)
        }
    }

    /// Full-perimeter loop; reverse direction after 1–2 complete laps.
    private func stepPerimeter(step: CGFloat, dt: TimeInterval) {
        let total = perimeterLength()
        pathProgress = (pathProgress + travelDir * step).truncatingRemainder(dividingBy: total)
        if pathProgress < 0 { pathProgress += total }
        distanceUntilReverse -= step
        if distanceUntilReverse <= 0 {
            travelDir = -travelDir
            distanceUntilReverse = total * CGFloat(Int.random(in: 1...2))
        }
        let p = pathPoint(pathProgress)
        window.setFrameOrigin(origin(forCenter: p.center))
        orientToEdge(tangent: p.tangent, dt: dt)
    }

    /// DVD-logo style: drift in a straight line, bounce off the screen walls.
    /// A bit brisker than edge-walking (1.2× the wander speed).
    private func stepScreensaver(step: CGFloat, dt: TimeInterval) {
        let move = step * Self.screensaverSpeedFactor
        let r = centerRect()
        ssCenter.x += ssVel.x * move
        ssCenter.y += ssVel.y * move
        if ssCenter.x <= r.minX { ssCenter.x = r.minX; ssVel.x = abs(ssVel.x) }
        if ssCenter.x >= r.maxX { ssCenter.x = r.maxX; ssVel.x = -abs(ssVel.x) }
        if ssCenter.y <= r.minY { ssCenter.y = r.minY; ssVel.y = abs(ssVel.y) }
        if ssCenter.y >= r.maxY { ssCenter.y = r.maxY; ssVel.y = -abs(ssVel.y) }
        window.setFrameOrigin(origin(forCenter: ssCenter))

        // Stay upright; face horizontal travel direction.
        let s = settings.size.scale
        let cur = scaleContainer.zRotation
        let delta = atan2(sin(-cur), cos(-cur))
        let maxStep = 8.0 * CGFloat(dt)
        scaleContainer.zRotation = cur + max(-maxStep, min(maxStep, delta))
        scaleContainer.yScale = s
        scaleContainer.xScale = ssVel.x >= 0 ? s : -s
    }

    /// Rotate the body so its feet stay on the current edge (toward the tangent)
    /// and mirror it to face the travel direction.
    private func orientToEdge(tangent: CGFloat, dt: TimeInterval) {
        let cur = scaleContainer.zRotation
        let delta = atan2(sin(tangent - cur), cos(tangent - cur)) // shortest turn
        let maxStep = 7.0 * CGFloat(dt)
        scaleContainer.zRotation = cur + max(-maxStep, min(maxStep, delta))
        let s = settings.size.scale
        scaleContainer.yScale = s
        scaleContainer.xScale = travelDir > 0 ? s : -s
    }


    /// Rectangle that the creature's CENTER walks around, inset from the visible
    /// frame by just the feet reach (+ a small gap) so Dochi hugs the edge. The
    /// (larger, transparent) window hangs off-screen beyond the edge.
    private func centerRect() -> NSRect {
        let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let gap: CGFloat = 6
        let inset = creatureReach + gap
        let w = max(vf.width - inset * 2, 1)
        let h = max(vf.height - inset * 2, 1)
        return NSRect(x: vf.minX + inset, y: vf.minY + inset, width: w, height: h)
    }

    private func perimeterLength() -> CGFloat {
        let r = centerRect()
        return 2 * (r.width + r.height)
    }

    /// Convert a creature-center point to the window's bottom-left origin.
    private func origin(forCenter c: NSPoint) -> NSPoint {
        NSPoint(x: c.x - windowSize.width / 2, y: c.y - windowSize.height / 2)
    }

    /// Map a perimeter distance to the creature CENTER and forward heading angle
    /// (direction of increasing progress; Dochi's snout points along this).
    private func pathPoint(_ progress: CGFloat) -> (center: NSPoint, tangent: CGFloat) {
        let r = centerRect()
        var d = progress
        // Bottom edge: left -> right (heading +x).
        if d < r.width {
            return (NSPoint(x: r.minX + d, y: r.minY), 0)
        }
        d -= r.width
        // Right edge: bottom -> top (heading +y).
        if d < r.height {
            return (NSPoint(x: r.maxX, y: r.minY + d), .pi / 2)
        }
        d -= r.height
        // Top edge: right -> left (heading -x / +pi).
        if d < r.width {
            return (NSPoint(x: r.maxX - d, y: r.maxY), .pi)
        }
        d -= r.width
        // Left edge: top -> bottom (heading -y).
        return (NSPoint(x: r.minX, y: r.maxY - d), -.pi / 2)
    }

    var windowFrame: NSRect { window.frame }
}
