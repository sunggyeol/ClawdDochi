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
    /// Last state applied, so a live restyle can re-apply the right gesture.
    private var currentState: AgentState = .idle

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
    private var distanceUntilReverse: CGFloat = 500

    /// Edge-walk speed per state. `waiting`/`done` stay put so the gesture reads.
    private func speed(for state: AgentState) -> CGFloat {
        switch state {
        case .idle:    return 22   // strolls around when Claude is done/idle
        case .working: return 38   // brisker pacing while busy
        case .waiting: return 0    // hold for the attention gesture
        case .done:    return 0    // hold for the celebration
        }
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
        applyGesture(currentState)
        applyVisibility()
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

    /// Run the gesture animation for `state` on the Dochi node.
    func applyGesture(_ state: AgentState) {
        currentState = state
        let node = dochi.node
        node.removeAction(forKey: DochiSprite.idleKey)
        node.removeAction(forKey: DochiSprite.gestureKey)
        node.removeAllActions()
        node.setScale(1); node.zRotation = 0
        node.position = baseNodePosition   // recover from any interrupted hop

        // Legs animate independently of the body gesture.
        dochi.animateLegs(for: state)

        wanderSpeed = speed(for: state)

        // Stationary states stand upright so the gesture reads cleanly; moving
        // states let stepWander rotate the body to face travel.
        if wanderSpeed == 0 {
            scaleContainer.zRotation = 0
            scaleContainer.xScale = settings.size.scale
            scaleContainer.yScale = settings.size.scale
        }

        switch state {
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
        }
    }

    /// Show the window and start the edge-wandering loop.
    func show() {
        // Start partway along the bottom edge.
        pathProgress = perimeterLength() * 0.15
        distanceUntilReverse = CGFloat.random(in: 300...700)
        window.setFrameOrigin(pathPoint(pathProgress).origin)
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

        let total = perimeterLength()
        let step = wanderSpeed * CGFloat(dt)

        // Advance along the perimeter in the current direction; occasionally
        // reverse so Dochi loops clockwise for a while, then the other way.
        pathProgress = (pathProgress + travelDir * step).truncatingRemainder(dividingBy: total)
        if pathProgress < 0 { pathProgress += total }
        distanceUntilReverse -= step
        if distanceUntilReverse <= 0 {
            travelDir = -travelDir
            distanceUntilReverse = CGFloat.random(in: 300...750)
        }

        let p = pathPoint(pathProgress)
        window.setFrameOrigin(p.origin)

        // Orient the body so its feet stay on the edge it's walking along
        // (rotate toward the edge tangent), and mirror it horizontally to point
        // the snout in the travel direction. This keeps Dochi upright when it
        // turns around on the bottom (just flips) and "climbs" the side walls,
        // always facing the way it's going — without ever going belly-up except
        // along the very top edge.
        let cur = scaleContainer.zRotation
        let delta = atan2(sin(p.tangent - cur), cos(p.tangent - cur)) // shortest turn
        let maxStep = 7.0 * CGFloat(dt)                                // smooth corner turns
        scaleContainer.zRotation = cur + max(-maxStep, min(maxStep, delta))

        let s = settings.size.scale
        scaleContainer.yScale = s
        scaleContainer.xScale = travelDir > 0 ? s : -s   // mirror when reversed
    }

    /// The rectangle (origin space) the window's bottom-left corner walks around.
    private func walkRect() -> NSRect {
        let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let w = max(vf.width - windowSize.width, 1)
        let h = max(vf.height - windowSize.height, 1)
        return NSRect(x: vf.minX, y: vf.minY, width: w, height: h)
    }

    private func perimeterLength() -> CGFloat {
        let r = walkRect()
        return 2 * (r.width + r.height)
    }

    /// Map a perimeter distance to a window origin and the forward heading angle
    /// (direction of increasing progress; Dochi's snout points along this).
    private func pathPoint(_ progress: CGFloat) -> (origin: NSPoint, tangent: CGFloat) {
        let r = walkRect()
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
