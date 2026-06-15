#!/usr/bin/env swift
//
//  generate-icon.swift
//  HiddenBarIcons
//
//  Renders the app icon (AppIcon.appiconset, 16–1024) and the three menu-bar
//  template glyphs (separator / collapse / expand) directly with AppKit +
//  CoreGraphics — no third-party tools. Re-run any time to regenerate:
//
//      swift scripts/generate-icon.swift [path/to/Assets.xcassets]
//
//  Theme: a MacBook notch with menu-bar icons being revealed from behind it.
//

import AppKit
import Foundation

let assetsPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "HiddenBarIcons/Resources/Assets.xcassets"

let fm = FileManager.default
let assetsURL = URL(fileURLWithPath: assetsPath)

// MARK: - Bitmap helper

/// Renders a square PNG of `px` pixels using the supplied AppKit drawing block.
/// The block receives the canvas side length in pixels (origin bottom-left).
func renderPNG(_ px: Int, _ draw: (CGFloat) -> Void) -> Data {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("Could not create bitmap rep") }
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGFloat(px))
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG")
    }
    return data
}

func write(_ data: Data, to dir: URL, _ name: String) {
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try! data.write(to: dir.appendingPathComponent(name))
}

func writeJSON(_ json: String, to dir: URL) {
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    try! json.data(using: .utf8)!.write(to: dir.appendingPathComponent("Contents.json"))
}

// MARK: - App icon

func drawAppIcon(_ s: CGFloat) {
    let inset = s * 0.092
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.2237
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Gradient background, clipped to the squircle.
    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.46, green: 0.41, blue: 0.97, alpha: 1.0), // indigo (top)
        NSColor(srgbRed: 0.29, green: 0.18, blue: 0.71, alpha: 1.0), // violet (bottom)
    ])!
    gradient.draw(in: rect, angle: -90)

    // Soft top sheen.
    let sheen = NSGradient(colors: [
        NSColor(white: 1.0, alpha: 0.16),
        NSColor(white: 1.0, alpha: 0.0),
    ])!
    sheen.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // MacBook-style notch at the top-center of the squircle.
    let notchW = rect.width * 0.36
    let notchH = rect.height * 0.085
    let notchRect = NSRect(x: rect.midX - notchW / 2, y: rect.maxY - notchH, width: notchW, height: notchH)
    let notch = NSBezierPath(roundedRect: notchRect, xRadius: notchH * 0.5, yRadius: notchH * 0.5)
    NSColor(srgbRed: 0.07, green: 0.05, blue: 0.16, alpha: 1.0).setFill()
    notch.fill()

    // Center motif: a left-pointing chevron "revealing" three icon dots.
    let cy = rect.midY - rect.height * 0.015
    let groupShift = -rect.width * 0.02
    let white = NSColor.white

    let chW = rect.width * 0.13
    let chH = rect.height * 0.12
    let chApexX = rect.midX - rect.width * 0.20 + groupShift
    let lineWidth = s * 0.033
    let chevron = NSBezierPath()
    chevron.lineWidth = lineWidth
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    chevron.move(to: NSPoint(x: chApexX + chW, y: cy + chH))
    chevron.line(to: NSPoint(x: chApexX, y: cy))
    chevron.line(to: NSPoint(x: chApexX + chW, y: cy - chH))
    white.setStroke()
    chevron.stroke()

    let dotR = rect.width * 0.037
    let firstDotX = rect.midX + groupShift
    let dotGap = rect.width * 0.115
    for i in 0..<3 {
        let dx = firstDotX + CGFloat(i) * dotGap
        white.setFill()
        NSBezierPath(ovalIn: NSRect(x: dx - dotR, y: cy - dotR, width: dotR * 2, height: dotR * 2)).fill()
    }
}

// MARK: - Menu-bar glyphs (template: solid black on transparent)

func drawSeparator(_ s: CGFloat) {
    let w = s * 0.13
    let h = s * 0.74
    let r = NSRect(x: s / 2 - w / 2, y: s / 2 - h / 2, width: w, height: h)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: r, xRadius: w / 2, yRadius: w / 2).fill()
}

func drawChevron(_ s: CGFloat, pointingRight: Bool) {
    let lineWidth = s * 0.12
    let halfW = s * 0.19
    let halfH = s * 0.27
    let cx = s / 2
    let cy = s / 2
    let p = NSBezierPath()
    p.lineWidth = lineWidth
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    if pointingRight {
        p.move(to: NSPoint(x: cx - halfW, y: cy + halfH))
        p.line(to: NSPoint(x: cx + halfW, y: cy))
        p.line(to: NSPoint(x: cx - halfW, y: cy - halfH))
    } else {
        p.move(to: NSPoint(x: cx + halfW, y: cy + halfH))
        p.line(to: NSPoint(x: cx - halfW, y: cy))
        p.line(to: NSPoint(x: cx + halfW, y: cy - halfH))
    }
    NSColor.black.setStroke()
    p.stroke()
}

// MARK: - Emit AppIcon.appiconset

let appIconDir = assetsURL.appendingPathComponent("AppIcon.appiconset")
struct IconSpec { let size: Int; let scale: Int }
let iconSpecs = [
    IconSpec(size: 16, scale: 1), IconSpec(size: 16, scale: 2),
    IconSpec(size: 32, scale: 1), IconSpec(size: 32, scale: 2),
    IconSpec(size: 128, scale: 1), IconSpec(size: 128, scale: 2),
    IconSpec(size: 256, scale: 1), IconSpec(size: 256, scale: 2),
    IconSpec(size: 512, scale: 1), IconSpec(size: 512, scale: 2),
]
var iconEntries: [String] = []
for spec in iconSpecs {
    let px = spec.size * spec.scale
    let name = "icon_\(spec.size)x\(spec.size)@\(spec.scale)x.png"
    write(renderPNG(px, drawAppIcon), to: appIconDir, name)
    iconEntries.append("""
        {
          "idiom" : "mac",
          "size" : "\(spec.size)x\(spec.size)",
          "scale" : "\(spec.scale)x",
          "filename" : "\(name)"
        }
    """)
}
writeJSON("""
{
  "images" : [
\(iconEntries.joined(separator: ",\n"))
  ],
  "info" : { "version" : 1, "author" : "xcode" }
}
""", to: appIconDir)

// MARK: - Emit glyph imagesets

func emitGlyph(_ name: String, _ draw: @escaping (CGFloat) -> Void) {
    let dir = assetsURL.appendingPathComponent("\(name).imageset")
    // 1x at 18px, 2x at 36px — comfortable for a ~22pt menu bar.
    write(renderPNG(18, draw), to: dir, "\(name).png")
    write(renderPNG(36, draw), to: dir, "\(name)@2x.png")
    writeJSON("""
    {
      "images" : [
        { "idiom" : "universal", "scale" : "1x", "filename" : "\(name).png" },
        { "idiom" : "universal", "scale" : "2x", "filename" : "\(name)@2x.png" }
      ],
      "info" : { "version" : 1, "author" : "xcode" },
      "properties" : { "template-rendering-intent" : "template" }
    }
    """, to: dir)
}

emitGlyph("separator", drawSeparator)
emitGlyph("collapse") { drawChevron($0, pointingRight: false) }
emitGlyph("expand") { drawChevron($0, pointingRight: true) }

// MARK: - Top-level catalog metadata

writeJSON("""
{
  "info" : { "version" : 1, "author" : "xcode" }
}
""", to: assetsURL)

print("Assets written to \(assetsURL.path)")
