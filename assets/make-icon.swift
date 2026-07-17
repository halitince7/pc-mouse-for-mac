#!/usr/bin/swift

// Generates the MacUtilities app icon (1024x1024 PNG).
// Usage: swift make-icon.swift <output.png>

import Cocoa

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = 1024.0

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fputs("no context\n", stderr); exit(1)
}

// Background: rounded square + diagonal gradient (purple -> blue)
let inset = 80.0
let rect = CGRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset)
let radius = 200.0
let bgPath = NSBezierPath(roundedRect: NSRectFromCGRect(rect), xRadius: radius, yRadius: radius)
bgPath.addClip()

let colors = [NSColor(calibratedRed: 0.42, green: 0.28, blue: 0.92, alpha: 1).cgColor,
              NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.98, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: size, y: 0),
                       options: [])

// Center: mouse + left/right arrows (desktop switching + scroll)
let cx = size / 2, cy = size / 2
let white = NSColor.white

// Mouse body (rounded vertical capsule)
let bodyW = 260.0, bodyH = 400.0
let body = NSBezierPath(roundedRect: NSRect(x: cx - bodyW/2, y: cy - bodyH/2, width: bodyW, height: bodyH),
                        xRadius: bodyW/2, yRadius: bodyW/2)
white.withAlphaComponent(0.95).setStroke()
body.lineWidth = 34
body.stroke()

// Scroll wheel (small vertical line near the top)
let wheel = NSBezierPath(roundedRect: NSRect(x: cx - 14, y: cy + 40, width: 28, height: 110),
                         xRadius: 14, yRadius: 14)
white.withAlphaComponent(0.95).setFill()
wheel.fill()

// Left / right chevron arrows (desktop switching)
func chevron(atX x: Double, pointingLeft: Bool) {
    let p = NSBezierPath()
    let w = 70.0, h = 120.0
    let tip = pointingLeft ? x - w/2 : x + w/2
    let back = pointingLeft ? x + w/2 : x - w/2
    p.move(to: NSPoint(x: back, y: cy + h/2))
    p.line(to: NSPoint(x: tip, y: cy))
    p.line(to: NSPoint(x: back, y: cy - h/2))
    white.withAlphaComponent(0.95).setStroke()
    p.lineWidth = 44
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    p.stroke()
}
chevron(atX: cx - 300, pointingLeft: true)
chevron(atX: cx + 300, pointingLeft: false)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("encode failed\n", stderr); exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
