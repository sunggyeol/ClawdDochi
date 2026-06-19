//
//  PreviewExporter.swift
//  ClawdDochi
//
//  Headless renderer for inspection. When the app is launched with
//  `--export-previews <dir>`, it renders Dochi's idle pose plus one
//  representative frame of each state to transparent PNGs and then terminates —
//  without showing a window or requiring interaction.
//
//  Pipeline: build dochiNode → apply static pose → SKView.texture(from:) →
//  NSBitmapImageRep → PNG on a transparent background.
//

import AppKit
import SpriteKit

@MainActor
enum PreviewExporter {

    /// Parse the launch arguments; returns the output directory if
    /// `--export-previews <dir>` is present.
    static func requestedDirectory() -> String? {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--export-previews") else { return nil }
        let next = idx + 1
        guard next < args.count else { return nil }
        return args[next]
    }

    /// Render every state pose to `<dir>/dochi-<state>.png`, then terminate.
    static func runAndExit(to dir: String) {
        let outURL = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: outURL,
                                                 withIntermediateDirectories: true)

        let canvas: CGFloat = 256
        var wrote: [String] = []

        for state in AgentState.allCases {
            if let png = renderPNG(state: state, canvas: canvas) {
                let fileURL = outURL.appendingPathComponent("dochi-\(state.rawValue).png")
                do {
                    try png.write(to: fileURL)
                    wrote.append(fileURL.path)
                } catch {
                    FileHandle.standardError.write(
                        Data("ClawdDochi: failed to write \(fileURL.path): \(error)\n".utf8))
                }
            } else {
                FileHandle.standardError.write(
                    Data("ClawdDochi: failed to render pose for \(state.rawValue)\n".utf8))
            }
        }

        // Also export a menu-bar silhouette frame (on gray so the black
        // template mask is visible) for inspection.
        if let mb = renderMenuBarPNG() {
            let url = outURL.appendingPathComponent("dochi-menubar.png")
            if (try? mb.write(to: url)) != nil { wrote.append(url.path) }
        }

        for path in wrote {
            print("exported \(path)")
        }
        NSApp.terminate(nil)
    }

    // MARK: - App icon

    /// `--export-icon <path.png>` writes a 1024×1024 app icon (Dochi on a soft
    /// rounded-square background) and exits.
    static func requestedIconPath() -> String? {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--export-icon"), idx + 1 < args.count
        else { return nil }
        return args[idx + 1]
    }

    static func renderIconAndExit(to path: String) {
        if let data = composeIcon(size: 1024) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("exported \(path)")
        } else {
            FileHandle.standardError.write(Data("ClawdDochi: failed to render icon\n".utf8))
        }
        NSApp.terminate(nil)
    }

    /// Compose the app icon: warm rounded-square background + the colored Dochi.
    private static func composeIcon(size: CGFloat) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let radius = size * 0.2237   // macOS app-icon corner ratio
        let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        // Cool blue background: high contrast against Dochi's warm cream/terracotta
        // tones so the hedgehog stays legible even at small (Dock/Finder) sizes.
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.66, green: 0.83, blue: 0.95, alpha: 1),  // sky blue (top)
            NSColor(calibratedRed: 0.40, green: 0.62, blue: 0.86, alpha: 1),  // deeper blue (bottom)
        ])
        gradient?.draw(in: bg, angle: -90)

        // Colored Dochi, centered, filling ~72% of the icon.
        if let cg = dochiCGImage(canvas: size * 0.72, appearance: .color) {
            let dw = size * 0.72
            let img = NSImage(cgImage: cg, size: NSSize(width: dw, height: dw))
            let drect = NSRect(x: (size - dw) / 2, y: (size - dw) / 2 - size * 0.015,
                               width: dw, height: dw)
            img.draw(in: drect)
        }

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    /// Render the idle Dochi to a transparent CGImage at the given canvas size.
    private static func dochiCGImage(canvas: CGFloat, appearance: DochiAppearance) -> CGImage? {
        let size = CGSize(width: canvas, height: canvas)
        let skView = SKView(frame: CGRect(origin: .zero, size: size))
        skView.allowsTransparency = true
        let scene = SKScene(size: size)
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        let sprite = DochiSprite(appearance: appearance)
        sprite.applyStaticPose(.idle)
        let scaleNode = SKNode()
        scaleNode.setScale(canvas / (DochiMetrics.canvasSize * 1.15))
        scaleNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        scaleNode.addChild(sprite.node)
        scene.addChild(scaleNode)
        skView.presentScene(scene)
        return skView.texture(from: scene)?.cgImage()
    }

    /// Render a single state pose to PNG data on a transparent background.
    private static func renderPNG(state: AgentState, canvas: CGFloat) -> Data? {
        let size = CGSize(width: canvas, height: canvas)
        let skView = SKView(frame: CGRect(origin: .zero, size: size))
        skView.allowsTransparency = true

        let scene = SKScene(size: size)
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill

        // Scale the creature up to comfortably fill the canvas.
        let args = CommandLine.arguments
        let appearance: DochiAppearance = {
            if let i = args.firstIndex(of: "--appearance"), i + 1 < args.count,
               let a = DochiAppearance(rawValue: args[i + 1]) { return a }
            return DochiSettings.shared.appearance
        }()
        let sprite = DochiSprite(appearance: appearance)
        sprite.applyStaticPose(state)

        let scaleNode = SKNode()
        let fit = canvas / (DochiMetrics.canvasSize * 1.15)
        scaleNode.setScale(fit)
        scaleNode.position = CGPoint(x: size.width / 2, y: size.height / 2)
        scaleNode.addChild(sprite.node)
        scene.addChild(scaleNode)

        skView.presentScene(scene)

        guard let texture = skView.texture(from: scene) else { return nil }
        let cg = texture.cgImage()
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = size
        return rep.representation(using: .png, properties: [:])
    }

    /// Render a horizontal strip of the working walk-cycle frames, scaled up on
    /// a gray background, so both the silhouette shape and the motion are visible
    /// for inspection.
    private static func renderMenuBarPNG() -> Data? {
        let scale: CGFloat = 10
        let frames = MenuBarSprite.frames(for: .working)
        let cols = frames.count
        let cellW = MenuBarSprite.size.width * scale
        let cellH = MenuBarSprite.size.height * scale
        let canvas = NSSize(width: cellW * CGFloat(cols), height: cellH)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(canvas.width),
            pixelsHigh: Int(canvas.height), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.85, alpha: 1).setFill()   // light, so the black template shows
        NSRect(origin: .zero, size: canvas).fill()
        for (i, frame) in frames.enumerated() {
            frame.draw(in: NSRect(x: CGFloat(i) * cellW, y: 0, width: cellW, height: cellH))
        }
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }
}
