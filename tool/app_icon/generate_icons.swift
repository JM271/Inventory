// Generates the app icon for iOS, Android and web from the Molenstraat
// wheel (assets/brand/wheel.png): the wheel in white on black.
//
//   swift tool/app_icon/generate_icons.swift
//
// Run from the project root. Every size each platform needs is rendered
// from the one source image, plus a 1024 px preview at
// tool/app_icon/app_icon.png.

import AppKit
import CoreGraphics
import Foundation

let black = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

guard
  let source = NSImage(contentsOfFile: "assets/brand/wheel.png")?
    .cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
  fatalError("assets/brand/wheel.png not found - run from the project root")
}

enum Variant {
  case ios  // opaque full square, OS applies the mask
  case rounded  // rounded tile on transparency (Android legacy, web, favicon)
  case maskable  // full-bleed, wheel inside the 80 % safe circle
  case foreground  // wheel only, Android adaptive foreground (66/108 safe zone)
}

/// Draws the wheel in white, `diameter` wide, centred on the 1024 canvas.
func drawWheel(_ c: CGContext, diameter d: CGFloat) {
  let rect = CGRect(x: 512 - d / 2, y: 512 - d / 2, width: d, height: d)
  // Render the wheel's shape into a grey mask (black wheel → opaque), then
  // fill white through it, so it works whatever background the PNG has.
  let px = 1024
  let gray = CGContext(
    data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
  gray.setFillColor(CGColor(gray: 1, alpha: 1))
  gray.fill(CGRect(x: 0, y: 0, width: px, height: px))
  gray.interpolationQuality = .high
  gray.draw(source, in: CGRect(x: 0, y: 0, width: px, height: px))
  // Image masks paint where the sample is 0 (black).
  let provider = gray.makeImage()!.dataProvider!
  let mask = CGImage(
    maskWidth: px, height: px, bitsPerComponent: 8, bitsPerPixel: 8,
    bytesPerRow: gray.bytesPerRow, provider: provider, decode: nil, shouldInterpolate: true)!
  c.saveGState()
  c.clip(to: rect, mask: mask)
  c.setFillColor(white)
  c.fill(rect)
  c.restoreGState()
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
  c.scaleBy(x: s / 1024, y: s / 1024)
  let full = CGRect(x: 0, y: 0, width: 1024, height: 1024)

  switch variant {
  case .ios:
    c.setFillColor(black)
    c.fill(full)
    drawWheel(c, diameter: 680)
  case .rounded:
    let inset = full.insetBy(dx: 40, dy: 40)
    c.addPath(CGPath(roundedRect: inset, cornerWidth: 210, cornerHeight: 210, transform: nil))
    c.setFillColor(black)
    c.fillPath()
    drawWheel(c, diameter: 640)
  case .maskable:
    c.setFillColor(black)
    c.fill(full)
    drawWheel(c, diameter: 640)  // radius 320 < 409 safe radius
  case .foreground:
    drawWheel(c, diameter: 560)  // radius 280 ≈ 30 dp of 108 dp, inside 33 dp
  }

  let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
  let data = rep.representation(using: .png, properties: [:])!
  let url = URL(fileURLWithPath: path)
  try! FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  try! data.write(to: url)
  print("  \(path) (\(size)px)")
}

// MARK: - Outputs

print("Molenstraat app icon")
render(.rounded, size: 1024, to: "tool/app_icon/app_icon.png")

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
