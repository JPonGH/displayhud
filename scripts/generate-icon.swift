import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate-icon.swift OUTPUT.png\n", stderr)
    exit(2)
}

let size = NSSize(width: 1024, height: 1024)
_ = NSApplication.shared
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 1024,
    pixelsHigh: 1024,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bitmapFormat: [],
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    fputs("unable to create icon bitmap\n", stderr)
    exit(1)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let canvas = NSRect(origin: .zero, size: size)
NSColor.clear.setFill()
canvas.fill()

let tile = NSBezierPath(roundedRect: canvas.insetBy(dx: 72, dy: 72), xRadius: 210, yRadius: 210)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1),
    NSColor(calibratedRed: 0.14, green: 0.16, blue: 0.22, alpha: 1),
])!
gradient.draw(in: tile, angle: -90)

let rail = NSBezierPath(roundedRect: NSRect(x: 218, y: 250, width: 588, height: 46), xRadius: 23, yRadius: 23)
NSColor.white.withAlphaComponent(0.18).setFill()
rail.fill()

let orange = NSBezierPath(roundedRect: NSRect(x: 218, y: 250, width: 294, height: 46), xRadius: 23, yRadius: 23)
NSColor.systemOrange.setFill()
orange.fill()

// Original monitor/brightness glyph drawn from primitives only.
// No symbols, no bundled artwork: a single monitor outline on a stand,
// with a brightness sun (filled disc plus eight rays) on its screen.
NSColor.white.setStroke()
NSColor.white.setFill()

let screen = NSBezierPath(roundedRect: NSRect(x: 312, y: 470, width: 400, height: 250), xRadius: 28, yRadius: 28)
screen.lineWidth = 26
screen.stroke()

let stand = NSBezierPath(roundedRect: NSRect(x: 496, y: 408, width: 32, height: 70), xRadius: 12, yRadius: 12)
stand.fill()

let base = NSBezierPath(roundedRect: NSRect(x: 422, y: 384, width: 180, height: 28), xRadius: 14, yRadius: 14)
base.fill()

let sunCenter = NSPoint(x: 512, y: 595)
let sun = NSBezierPath(ovalIn: NSRect(x: sunCenter.x - 44, y: sunCenter.y - 44, width: 88, height: 88))
sun.fill()

let rays = NSBezierPath()
rays.lineWidth = 18
rays.lineCapStyle = .round
for i in 0..<8 {
    let angle = CGFloat(i) * .pi / 4
    rays.move(to: NSPoint(x: sunCenter.x + cos(angle) * 68, y: sunCenter.y + sin(angle) * 68))
    rays.line(to: NSPoint(x: sunCenter.x + cos(angle) * 96, y: sunCenter.y + sin(angle) * 96))
}
rays.stroke()
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("unable to render icon\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
