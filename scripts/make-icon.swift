// Draws the app icon (a branching commit graph) and writes Resources/AppIcon.icns.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024

    // Rounded-square background with a subtle gradient.
    let inset = 100 * s
    let tile = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2),
                            xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1),
               ending: NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1))!.draw(in: tile, angle: -90)

    let teal = NSColor(red: 0.13, green: 0.71, blue: 0.86, alpha: 1)
    let purple = NSColor(red: 0.58, green: 0.40, blue: 0.94, alpha: 1)
    let main = 400 * s, side = 640 * s

    func stroke(_ path: NSBezierPath, _ colour: NSColor) {
        path.lineWidth = 56 * s
        path.lineCapStyle = .round
        colour.setStroke()
        path.stroke()
    }
    let trunk = NSBezierPath()
    trunk.move(to: NSPoint(x: main, y: 230 * s))
    trunk.line(to: NSPoint(x: main, y: 794 * s))
    stroke(trunk, teal)

    let branch = NSBezierPath()
    branch.move(to: NSPoint(x: main, y: 330 * s))
    branch.curve(to: NSPoint(x: side, y: 520 * s), controlPoint1: NSPoint(x: main, y: 450 * s), controlPoint2: NSPoint(x: side, y: 400 * s))
    branch.line(to: NSPoint(x: side, y: 560 * s))
    branch.curve(to: NSPoint(x: main, y: 720 * s), controlPoint1: NSPoint(x: side, y: 660 * s), controlPoint2: NSPoint(x: main, y: 610 * s))
    stroke(branch, purple)

    func node(_ x: CGFloat, _ y: CGFloat, _ colour: NSColor) {
        let r = 62 * s
        let circle = NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        NSColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 1).setFill()
        circle.fill()
        circle.lineWidth = 36 * s
        colour.setStroke()
        circle.stroke()
    }
    node(main, 260 * s, teal)
    node(main, 520 * s, teal)
    node(side, 540 * s, purple)
    node(main, 770 * s, teal)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(size: CGFloat(base * scale)).representation(using: .png, properties: [:])!
        try! data.write(to: iconset.appendingPathComponent(name))
    }
}
try! fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "✓ Wrote Resources/AppIcon.icns" : "iconutil failed")
