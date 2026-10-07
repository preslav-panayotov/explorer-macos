// Generates Resources/AppIcon.icns — run: swift Tools/make_icon.swift
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
func gradient(_ path: NSBezierPath, _ top: UInt32, _ bottom: UInt32) {
    NSGradient(starting: color(top), ending: color(bottom))!.draw(in: path, angle: -90)
}

// macOS-style rounded square plate
let plate = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 190, yRadius: 190)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.30).cgColor)
color(0xFFFFFF).setFill(); plate.fill()
ctx.restoreGState()
gradient(plate, 0xFAFCFF, 0xD5E2F2)

// folder back (with tab)
let back = NSBezierPath()
back.move(to: NSPoint(x: 210, y: 300))
back.line(to: NSPoint(x: 210, y: 700))
back.curve(to: NSPoint(x: 245, y: 735), controlPoint1: NSPoint(x: 210, y: 720), controlPoint2: NSPoint(x: 225, y: 735))
back.line(to: NSPoint(x: 400, y: 735))
back.curve(to: NSPoint(x: 440, y: 710), controlPoint1: NSPoint(x: 420, y: 735), controlPoint2: NSPoint(x: 430, y: 725))
back.line(to: NSPoint(x: 470, y: 672))
back.line(to: NSPoint(x: 780, y: 672))
back.curve(to: NSPoint(x: 814, y: 640), controlPoint1: NSPoint(x: 800, y: 672), controlPoint2: NSPoint(x: 814, y: 656))
back.line(to: NSPoint(x: 814, y: 300))
back.close()
gradient(back, 0xF2B21B, 0xDE9A00)

// paper sheet peeking out, with blue "list" bars (the Explorer motif)
let paper = NSBezierPath(roundedRect: NSRect(x: 262, y: 400, width: 500, height: 330), xRadius: 22, yRadius: 22)
color(0x000000, 0.18).setFill()
NSBezierPath(roundedRect: NSRect(x: 262, y: 394, width: 500, height: 330), xRadius: 22, yRadius: 22).fill()
color(0xFFFFFF).setFill(); paper.fill()
for (i, w) in [380, 300, 340].enumerated() {
    let bar = NSBezierPath(roundedRect: NSRect(x: 306, y: 650 - CGFloat(i) * 62, width: CGFloat(w), height: 26), xRadius: 13, yRadius: 13)
    color(i == 0 ? 0x0067C0 : 0x9CC4EC).setFill(); bar.fill()
}

// folder front
let front = NSBezierPath(roundedRect: NSRect(x: 190, y: 250, width: 644, height: 340), xRadius: 40, yRadius: 40)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: NSColor.black.withAlphaComponent(0.25).cgColor)
color(0xFFD45A).setFill(); front.fill()
ctx.restoreGState()
gradient(front, 0xFFE07A, 0xFFC12E)
let sheen = NSBezierPath(roundedRect: NSRect(x: 190, y: 530, width: 644, height: 60), xRadius: 30, yRadius: 30)
color(0xFFFFFF, 0.18).setFill(); sheen.fill()

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
let out = URL(filePath: FileManager.default.currentDirectoryPath)
let iconset = out.appending(path: ".icon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let master = iconset.appending(path: "master.png")
try png.write(to: master)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128),
                   ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let p = Process(); p.executableURL = URL(filePath: "/usr/bin/sips")
    p.arguments = ["-z", "\(px)", "\(px)", master.path, "--out", iconset.appending(path: "\(name).png").path]
    p.standardOutput = FileHandle.nullDevice; try p.run(); p.waitUntilExit()
}
try FileManager.default.removeItem(at: master)
let ic = Process(); ic.executableURL = URL(filePath: "/usr/bin/iconutil")
ic.arguments = ["-c", "icns", iconset.path, "-o", out.appending(path: "Resources/AppIcon.icns").path]
try ic.run(); ic.waitUntilExit()
try FileManager.default.removeItem(at: iconset)
try png.write(to: out.appending(path: "docs/icon.png"))
print("Wrote Resources/AppIcon.icns and docs/icon.png")
