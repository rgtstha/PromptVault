#!/usr/bin/env swift
// Generates the PromptVault app icon at every size required by the asset catalog.
// Usage: swift scripts/generate-icon.swift PromptVault/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

func renderIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("Couldn't create bitmap") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext

    // macOS icon grid: the shape is ~80% of the canvas with a continuous-corner radius.
    let inset = size * 0.098
    let shapeRect = CGRect(x: inset, y: inset * 1.15, width: size - inset * 2, height: size - inset * 2)
    let radius = shapeRect.width * 0.225
    let shape = NSBezierPath(roundedRect: shapeRect, xRadius: radius, yRadius: radius)

    // Soft drop shadow.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.03,
                      color: NSColor.black.withAlphaComponent(0.28).cgColor)
    NSColor.black.setFill()
    shape.fill()
    context.restoreGState()

    // Indigo → violet gradient body.
    context.saveGState()
    shape.addClip()
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.33, green: 0.36, blue: 0.93, alpha: 1),
        NSColor(srgbRed: 0.55, green: 0.33, blue: 0.95, alpha: 1),
    ])!
    gradient.draw(in: shapeRect, angle: -60)

    // Subtle top highlight.
    let highlight = NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
    highlight.draw(in: CGRect(x: shapeRect.minX, y: shapeRect.midY, width: shapeRect.width, height: shapeRect.height / 2), angle: -90)
    context.restoreGState()

    // Speech bubble glyph with text lines.
    let lineColor = NSColor(srgbRed: 0.42, green: 0.36, blue: 0.94, alpha: 1)
    let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.40, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [lineColor, .white]))
    if let symbol = NSImage(systemSymbolName: "text.bubble.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let symbolSize = symbol.size
        let origin = CGPoint(x: shapeRect.midX - symbolSize.width / 2, y: shapeRect.midY - symbolSize.height / 2 - size * 0.01)
        symbol.draw(in: CGRect(origin: origin, size: symbolSize), from: .zero, operation: .sourceOver, fraction: 1)
    }

    // Small sparkle to hint at AI.
    let sparkleConfiguration = NSImage.SymbolConfiguration(pointSize: size * 0.15, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(srgbRed: 1, green: 0.86, blue: 0.45, alpha: 1)]))
    if let sparkle = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)?
        .withSymbolConfiguration(sparkleConfiguration) {
        let sparkleSize = sparkle.size
        let origin = CGPoint(x: shapeRect.maxX - sparkleSize.width - size * 0.11, y: shapeRect.maxY - sparkleSize.height - size * 0.10)
        sparkle.draw(in: CGRect(origin: origin, size: sparkleSize), from: .zero, operation: .sourceOver, fraction: 1)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let specs: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for spec in specs {
    let pixels = spec.points * spec.scale
    let filename = "icon_\(spec.points)x\(spec.points)\(spec.scale == 2 ? "@2x" : "").png"
    try renderIcon(pixels: pixels).write(to: outputDirectory.appendingPathComponent(filename))
    images.append(["filename": filename, "idiom": "mac", "scale": "\(spec.scale)x", "size": "\(spec.points)x\(spec.points)"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outputDirectory.appendingPathComponent("Contents.json"))
print("Wrote \(specs.count) icon sizes to \(outputDirectory.path)")
