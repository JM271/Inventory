// Generates the Spoke app icon for iOS, Android and web.
//
//   swift tool/app_icon/generate_icons.swift
//
// Run from the project root. The design is defined once below (on a
// 1024 × 1024 canvas) and rendered into every size each platform needs,
// plus an SVG master at tool/app_icon/spoke_logo.svg.

import AppKit
import CoreGraphics
import Foundation

// MARK: - Brand

struct RGB {
  let r, g, b: CGFloat
  init(_ hex: UInt32) {
    r = CGFloat((hex >> 16) & 0xFF) / 255
    g = CGFloat((hex >> 8) & 0xFF) / 255
    b = CGFloat(hex & 0xFF) / 255
  }
  var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
  var hex: String { String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255)) }
}

let greenTop = RGB(0x2F7560)
let greenBottom = RGB(0x1F5444)
let cream = RGB(0xF5F6F2)
let amber = RGB(0xECC58B)
let ink = RGB(0x172C29)

// MARK: - Geometry (1024 canvas, centre 512,512)

let tireRadius: CGFloat = 330
let tireWidth: CGFloat = 60
let rimRadius: CGFloat = 282  // thin inner rim line
let rimWidth: CGFloat = 12
let spokeCount = 16
let spokeWidth: CGFloat = 10
let spokeHubRadius: CGFloat = 52
// Offset = an odd number of spoke spacings so rim holes stay evenly spaced (3-cross).
let spokeLace: CGFloat = 3 * 2 * .pi / CGFloat(spokeCount)
let hubRadius: CGFloat = 80
let axleRadius: CGFloat = 26

func spokes() -> [(CGPoint, CGPoint)] {
  (0..<spokeCount).map { i in
    let a = CGFloat(i) * 2 * .pi / CGFloat(spokeCount) - .pi / 2
    let d = i % 2 == 0 ? spokeLace : -spokeLace
    let h = CGPoint(x: 512 + spokeHubRadius * cos(a), y: 512 + spokeHubRadius * sin(a))
    let r = CGPoint(x: 512 + rimRadius * cos(a + d), y: 512 + rimRadius * sin(a + d))
    return (h, r)
  }
}

// MARK: - Rendering

enum Variant {
  case ios  // opaque full square, OS applies the mask
  case rounded  // rounded tile on transparency (Android legacy, web, favicon)
  case maskable  // full-bleed, wheel inside the 80 % safe circle
  case foreground  // wheel only, Android adaptive foreground (66/108 safe zone)
}

func drawBackground(_ c: CGContext, _ rect: CGRect) {
  let g = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [greenTop.cg, greenBottom.cg] as CFArray, locations: [0, 1])!
  c.drawLinearGradient(
    g, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
}

func drawWheel(_ c: CGContext) {
  let centre = CGPoint(x: 512, y: 512)
  c.setLineCap(.round)

  // Spokes
  c.setStrokeColor(cream.cg.copy(alpha: 0.9)!)
  c.setLineWidth(spokeWidth)
  for (a, b) in spokes() {
    c.move(to: a)
    c.addLine(to: b)
  }
  c.strokePath()

  // Rim
  c.setStrokeColor(amber.cg)
  c.setLineWidth(rimWidth)
  c.addArc(center: centre, radius: rimRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
  c.strokePath()

  // Tyre
  c.setStrokeColor(cream.cg)
  c.setLineWidth(tireWidth)
  c.addArc(center: centre, radius: tireRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
  c.strokePath()

  // Hub + axle
  c.setFillColor(amber.cg)
  c.fillEllipse(in: CGRect(x: 512 - hubRadius, y: 512 - hubRadius, width: hubRadius * 2, height: hubRadius * 2))
  c.setFillColor(ink.cg)
  c.fillEllipse(in: CGRect(x: 512 - axleRadius, y: 512 - axleRadius, width: axleRadius * 2, height: axleRadius * 2))
}

func render(_ variant: Variant, size: Int, to path: String) {
  let s = CGFloat(size)
  let c = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: variant == .ios
      ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
  c.interpolationQuality = .high
  c.setShouldAntialias(true)
  // Work in a top-left origin 1024 canvas.
  c.translateBy(x: 0, y: s)
  c.scaleBy(x: s / 1024, y: -s / 1024)
  let full = CGRect(x: 0, y: 0, width: 1024, height: 1024)

  var wheelScale: CGFloat = 1
  switch variant {
  case .ios:
    drawBackground(c, full)
  case .rounded:
    let inset = full.insetBy(dx: 40, dy: 40)
    c.saveGState()
    c.addPath(CGPath(roundedRect: inset, cornerWidth: 210, cornerHeight: 210, transform: nil))
    c.clip()
    drawBackground(c, inset)
    c.restoreGState()
    wheelScale = 0.92
  case .maskable:
    drawBackground(c, full)
    wheelScale = 0.98  // outer tyre edge = 360 * 0.98 ≈ 353 < 409 safe radius
  case .foreground:
    wheelScale = 0.80  // 360 * 0.8 = 288 ≈ 30 dp of 108 dp, inside 33 dp safe radius
  }
  c.translateBy(x: 512, y: 512)
  c.scaleBy(x: wheelScale, y: wheelScale)
  c.translateBy(x: -512, y: -512)
  drawWheel(c)

  let image = c.makeImage()!
  let rep = NSBitmapImageRep(cgImage: image)
  let data = rep.representation(using: .png, properties: [:])!
  let url = URL(fileURLWithPath: path)
  try! FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try! data.write(to: url)
  print("  \(path) (\(size)px)")
}

func writeSVG(to path: String) {
  let lines = spokes().map {
    String(format: "    <line x1=\"%.1f\" y1=\"%.1f\" x2=\"%.1f\" y2=\"%.1f\"/>", $0.0.x, $0.0.y, $0.1.x, $0.1.y)
  }.joined(separator: "\n")
  let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
      <defs>
        <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="\(greenTop.hex)"/>
          <stop offset="1" stop-color="\(greenBottom.hex)"/>
        </linearGradient>
      </defs>
      <rect x="40" y="40" width="944" height="944" rx="210" fill="url(#bg)"/>
      <g transform="translate(512 512) scale(0.92) translate(-512 -512)">
        <g stroke="\(cream.hex)" stroke-opacity="0.9" stroke-width="\(Int(spokeWidth))" stroke-linecap="round">
    \(lines)
        </g>
        <circle cx="512" cy="512" r="\(Int(rimRadius))" fill="none" stroke="\(amber.hex)" stroke-width="\(Int(rimWidth))"/>
        <circle cx="512" cy="512" r="\(Int(tireRadius))" fill="none" stroke="\(cream.hex)" stroke-width="\(Int(tireWidth))"/>
        <circle cx="512" cy="512" r="\(Int(hubRadius))" fill="\(amber.hex)"/>
        <circle cx="512" cy="512" r="\(Int(axleRadius))" fill="\(ink.hex)"/>
      </g>
    </svg>

    """
  try! svg.write(toFile: path, atomically: true, encoding: .utf8)
  print("  \(path)")
}

// MARK: - Outputs

print("Spoke app icon")
writeSVG(to: "tool/app_icon/spoke_logo.svg")
render(.rounded, size: 1024, to: "tool/app_icon/spoke_logo.png")

let ios = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for (name, px) in [
  ("20x20@1x", 20), ("20x20@2x", 40), ("20x20@3x", 60),
  ("29x29@1x", 29), ("29x29@2x", 58), ("29x29@3x", 87),
  ("40x40@1x", 40), ("40x40@2x", 80), ("40x40@3x", 120),
  ("60x60@2x", 120), ("60x60@3x", 180),
  ("76x76@1x", 76), ("76x76@2x", 152), ("83.5x83.5@2x", 167),
  ("1024x1024@1x", 1024),
] {
  render(.ios, size: px, to: "\(ios)/Icon-App-\(name).png")
}

let res = "android/app/src/main/res"
for (dpi, legacy, adaptive) in [
  ("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216),
  ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432),
] {
  render(.rounded, size: legacy, to: "\(res)/mipmap-\(dpi)/ic_launcher.png")
  render(.foreground, size: adaptive, to: "\(res)/mipmap-\(dpi)/ic_launcher_foreground.png")
}

render(.rounded, size: 32, to: "web/favicon.png")
render(.rounded, size: 192, to: "web/icons/Icon-192.png")
render(.rounded, size: 512, to: "web/icons/Icon-512.png")
render(.maskable, size: 192, to: "web/icons/Icon-maskable-192.png")
render(.maskable, size: 512, to: "web/icons/Icon-maskable-512.png")
print("Done.")
