#!/usr/bin/swift

// Generates the MacUtilities app icon (1024x1024 PNG).
// Usage: swift make-icon.swift <output.png>
//
// Design: a clean white mouse glyph flanked by left/right chevrons (desktop
// switching) on a graphite squircle with a subtle same-hue vertical gradient
// (light top -> deeper bottom), Apple-style.

import Cocoa

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let size = 1024.0

func hex(_ s: String) -> NSColor {
    var h = UInt64(); Scanner(string: s).scanHexInt64(&h)
    return NSColor(calibratedRed: CGFloat((h >> 16) & 0xff) / 255,
                   green: CGFloat((h >> 8) & 0xff) / 255,
                   blue: CGFloat(h & 0xff) / 255, alpha: 1)
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else {
    fputs("no context\n", stderr); exit(1)
}

// Background: rounded square (squircle) clip + subtle vertical graphite gradient
let inset = 80.0
let rect = CGRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset)
let bg = NSBezierPath(roundedRect: NSRectFromCGRect(rect), xRadius: 210, yRadius: 210)
bg.addClip()

let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [hex("3A3F4B").cgColor, hex("1C1F26").cgColor] as CFArray,
                          locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: size/2, y: size),
                       end: CGPoint(x: size/2, y: 0),
                       options: [])

// Center: white mouse glyph + left/right chevrons
let cx = size / 2, cy = size / 2
let glyph = NSColor.white

// Mouse body (rounded vertical capsule)
let bodyW = 250.0, bodyH = 390.0
let body = NSBezierPath(roundedRect: NSRect(x: cx - bodyW/2, y: cy - bodyH/2, width: bodyW, height: bodyH),
                        xRadius: bodyW/2, yRadius: bodyW/2)
glyph.setStroke()
body.lineWidth = 34
body.stroke()

// Scroll wheel (small vertical line near the top)
let wheel = NSBezierPath(roundedRect: NSRect(x: cx - 14, y: cy + 40, width: 28, height: 110),
                         xRadius: 14, yRadius: 14)
glyph.setFill()
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
    glyph.setStroke()
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
