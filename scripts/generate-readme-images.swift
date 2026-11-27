#!/usr/bin/env swift
// Builds the README images (banner, how-it-works strip, feature screenshots) from the opt-in
// snapshot test renders, which use a throwaway library filled with the sample prompts.
//
// 1. Render the screens:
//    TEST_RUNNER_PROMPTVAULT_SNAPSHOT_DIR=/tmp/pv-snaps xcodebuild -project PromptVault.xcodeproj \
//      -scheme PromptVault -derivedDataPath build/DerivedData test -only-testing:PromptVaultTests/SnapshotRenderTests
// 2. Compose the images (run from the repository root):
//    swift scripts/generate-readme-images.swift /tmp/pv-snaps docs/images
import AppKit

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/generate-readme-images.swift <snapshot-dir> <output-dir>\n".utf8))
    exit(1)
}
let snapshotDirectory = URL(fileURLWithPath: arguments[0])
let outputDirectory = URL(fileURLWithPath: arguments[1])
let iconURL = URL(fileURLWithPath: "PromptVault/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png")
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// MARK: - Palette (matches the app icon)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let indigo = rgb(0.33, 0.36, 0.93)
let violet = rgb(0.55, 0.33, 0.95)
let ink = rgb(0.10, 0.10, 0.16)
let muted = rgb(0.36, 0.36, 0.46)
let backdropTop = rgb(0.972, 0.968, 1.0)
let backdropBottom = rgb(0.918, 0.912, 0.992)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Loading

func loadImage(_ url: URL) -> CGImage {
    guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data), let image = rep.cgImage else {
        fatalError("Couldn't read \(url.path). Render the snapshots first (see the top of this script).")
    }
    return image
}

func snapshot(_ name: String) -> CGImage { loadImage(snapshotDirectory.appendingPathComponent("\(name).png")) }

/// Crops in pixels, measured from the top-left corner.
func crop(_ image: CGImage, left: Int = 0, top: Int = 0, right: Int = 0, bottom: Int = 0) -> CGImage {
    image.cropping(to: CGRect(x: left, y: top, width: image.width - left - right, height: image.height - top - bottom))!
}

/// Point size for drawing a 2x snapshot at 1:1 pixels.
func pointSize(_ image: CGImage, scale: CGFloat = 0.5) -> CGSize {
    CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
}

// MARK: - Canvas (top-left origin, drawn at 2x)

final class Canvas {
    let size: CGSize
    let scale: CGFloat
    let context: CGContext
    private let rep: NSBitmapImageRep

    /// Draws at up to 2x, capped at `maxPixelWidth`: GitHub never shows README images wider than
    /// about 1000 points, so extra pixels only add weight to the repository.
    init(width: CGFloat, height: CGFloat, maxPixelWidth: CGFloat = 2000) {
        let scale = min(2, maxPixelWidth / width)
        size = CGSize(width: width, height: height)
        self.scale = scale
        rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        context = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    }

    func write(_ name: String) {
        NSGraphicsContext.restoreGraphicsState()
        let data = rep.representation(using: .png, properties: [:])!
        try! data.write(to: outputDirectory.appendingPathComponent(name))
        print("wrote \(name) (\(rep.pixelsWide)×\(rep.pixelsHigh), \(data.count / 1024) KB)")
    }

    func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// Shadow offsets and blur are in device space, which is unflipped and scaled.
    func setShadow(down: CGFloat, blur: CGFloat, color: NSColor) {
        context.setShadow(offset: CGSize(width: 0, height: -down * scale), blur: blur * scale, color: color.cgColor)
    }

    func fill(_ path: CGPath, gradient colors: [NSColor], from start: CGPoint, to end: CGPoint) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        let gradient = CGGradient(colorsSpace: sRGB, colors: colors.map(\.cgColor) as CFArray, locations: nil)!
        context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
    }

    func fill(_ path: CGPath, _ color: NSColor) {
        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath()
    }

    func stroke(_ path: CGPath, _ color: NSColor, width: CGFloat) {
        context.addPath(path)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.strokePath()
    }

    func glow(at center: CGPoint, radius: CGFloat, color: NSColor) {
        let gradient = CGGradient(colorsSpace: sRGB, colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    func draw(_ image: CGImage, in rect: CGRect) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    /// A screenshot on a rounded card with a soft shadow and a hairline edge.
    func panel(_ image: CGImage, in rect: CGRect, radius: CGFloat = 14, shadow: CGFloat = 0.20) {
        let path = rounded(rect, radius)
        context.saveGState()
        setShadow(down: 12, blur: 34, color: rgb(0.12, 0.08, 0.35, shadow))
        fill(path, .white)
        context.restoreGState()
        context.saveGState()
        context.addPath(path)
        context.clip()
        draw(image, in: rect)
        context.restoreGState()
        stroke(path, rgb(0, 0, 0, 0.12), width: 0.75)
    }

    @discardableResult
    func text(_ string: String, at point: CGPoint, font: NSFont, color: NSColor, width: CGFloat = 2_000,
              alignment: NSTextAlignment = .left, lineSpacing: CGFloat = 0) -> CGSize {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineSpacing = lineSpacing
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
        return text(attributed, at: point, width: width)
    }

    @discardableResult
    func text(_ attributed: NSAttributedString, at point: CGPoint, width: CGFloat) -> CGSize {
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let bounds = attributed.boundingRect(with: CGSize(width: width, height: 10_000), options: options)
        attributed.draw(with: CGRect(x: point.x, y: point.y, width: width, height: ceil(bounds.height) + 2), options: options)
        return bounds.size
    }

    func textWidth(_ string: String, font: NSFont) -> CGFloat {
        ceil(NSAttributedString(string: string, attributes: [.font: font]).size().width)
    }

    enum KeyStyle { case onColor, onLight }

    /// Draws a keyboard key and returns its width.
    @discardableResult
    func keycap(_ label: String, at origin: CGPoint, height: CGFloat, style: KeyStyle) -> CGFloat {
        let font = NSFont.systemFont(ofSize: height * 0.46, weight: .semibold)
        let width = max(height, textWidth(label, font: font) + height * 0.6)
        let rect = CGRect(x: origin.x, y: origin.y, width: width, height: height)
        let path = rounded(rect, height * 0.22)
        context.saveGState()
        switch style {
        case .onColor:
            setShadow(down: 3, blur: 0, color: rgb(0.10, 0.05, 0.35, 0.45))
            fill(path, rgb(1, 1, 1, 0.96))
        case .onLight:
            setShadow(down: 2, blur: 0, color: rgb(0.55, 0.55, 0.68, 0.55))
            fill(path, .white)
        }
        context.restoreGState()
        if style == .onLight { stroke(path, rgb(0.78, 0.78, 0.86), width: 1) }
        let labelColor = style == .onColor ? rgb(0.24, 0.22, 0.62) : ink
        let labelSize = NSAttributedString(string: label, attributes: [.font: font]).size()
        text(label, at: CGPoint(x: rect.midX - labelSize.width / 2, y: rect.midY - labelSize.height / 2 - 1), font: font, color: labelColor)
        return width
    }

    func backdrop(radius: CGFloat = 28) {
        let rect = CGRect(origin: .zero, size: size)
        let path = rounded(rect, radius)
        fill(path, gradient: [backdropTop, backdropBottom], from: .zero, to: CGPoint(x: 0, y: size.height))
        context.saveGState()
        context.addPath(path)
        context.clip()
        glow(at: CGPoint(x: size.width * 0.85, y: 0), radius: size.width * 0.45, color: rgb(0.70, 0.64, 1.0, 0.30))
        glow(at: CGPoint(x: 0, y: size.height), radius: size.width * 0.40, color: rgb(0.60, 0.70, 1.0, 0.22))
        context.restoreGState()
        stroke(rounded(rect.insetBy(dx: 0.5, dy: 0.5), radius), rgb(0.42, 0.40, 0.80, 0.16), width: 1)
    }

    func arrow(centeredAt center: CGPoint) {
        let circle = CGRect(x: center.x - 20, y: center.y - 20, width: 40, height: 40)
        context.saveGState()
        setShadow(down: 4, blur: 12, color: rgb(0.20, 0.15, 0.55, 0.18))
        fill(CGPath(ellipseIn: circle, transform: nil), .white)
        context.restoreGState()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x - 8, y: center.y))
        path.addLine(to: CGPoint(x: center.x + 8, y: center.y))
        path.move(to: CGPoint(x: center.x + 1, y: center.y - 7))
        path.addLine(to: CGPoint(x: center.x + 8, y: center.y))
        path.addLine(to: CGPoint(x: center.x + 1, y: center.y + 7))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        stroke(path, indigo, width: 3)
    }

    func stepBadge(_ number: Int, at origin: CGPoint, diameter: CGFloat = 34) {
        let rect = CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))
        fill(CGPath(ellipseIn: rect, transform: nil), gradient: [indigo, violet], from: CGPoint(x: rect.minX, y: rect.minY), to: CGPoint(x: rect.maxX, y: rect.maxY))
        let font = NSFont.systemFont(ofSize: diameter * 0.52, weight: .bold)
        let label = "\(number)"
        let labelSize = NSAttributedString(string: label, attributes: [.font: font]).size()
        text(label, at: CGPoint(x: rect.midX - labelSize.width / 2, y: rect.midY - labelSize.height / 2), font: font, color: .white)
    }
}

// MARK: - Banner

/// The README banner (wide and short), or with `height: 640` the 1280×640 social preview image that
/// GitHub shows when the repository link is shared. `dy` moves the text block down to stay centered.
func makeBanner(height: CGFloat = 440, dy: CGFloat = 0, popoverTop: CGFloat = 56, maxPixelWidth: CGFloat = 2000, cornerRadius: CGFloat = 24, output: String = "banner.png") {
    let width: CGFloat = 1280
    let canvas = Canvas(width: width, height: height, maxPixelWidth: maxPixelWidth)
    let shape = canvas.rounded(CGRect(x: 0, y: 0, width: width, height: height), cornerRadius)
    canvas.fill(shape, gradient: [rgb(0.27, 0.31, 0.89), rgb(0.43, 0.33, 0.94), rgb(0.60, 0.34, 0.94)],
                from: .zero, to: CGPoint(x: width, y: height))

    canvas.context.saveGState()
    canvas.context.addPath(shape)
    canvas.context.clip()
    canvas.glow(at: CGPoint(x: width * 0.80, y: 40), radius: 560, color: rgb(1, 1, 1, 0.20))
    canvas.glow(at: CGPoint(x: 80, y: height + 40), radius: 460, color: rgb(0.16, 0.10, 0.55, 0.40))

    // Left: icon, name, tagline, shortcut.
    canvas.draw(loadImage(iconURL), in: CGRect(x: 60, y: 66 + dy, width: 132, height: 132))
    canvas.text("PromptVault", at: CGPoint(x: 202, y: 90 + dy), font: .systemFont(ofSize: 68, weight: .bold), color: .white)
    canvas.text("Your AI prompts, one keystroke away.", at: CGPoint(x: 76, y: 212 + dy),
                font: .systemFont(ofSize: 34, weight: .semibold), color: .white)
    canvas.text("A native macOS menu bar app. Fully offline, no account.", at: CGPoint(x: 77, y: 262 + dy),
                font: .systemFont(ofSize: 21, weight: .regular), color: rgb(1, 1, 1, 0.84))
    var x: CGFloat = 77
    for key in ["⌃", "⌥", "P"] {
        x += canvas.keycap(key, at: CGPoint(x: x, y: 316 + dy), height: 48, style: .onColor) + 10
    }
    canvas.text("from any app, then type and press ↩", at: CGPoint(x: x + 8, y: 327 + dy),
                font: .systemFont(ofSize: 21, weight: .medium), color: rgb(1, 1, 1, 0.88))

    // Right: the popover, rising from the bottom edge.
    let popover = snapshot("popover-list-light")
    canvas.panel(popover, in: CGRect(origin: CGPoint(x: width - 400 - 84, y: popoverTop), size: pointSize(popover)), radius: 16, shadow: 0.45)
    canvas.context.restoreGState()
    canvas.write(output)
}

// MARK: - How it works

func makeHowItWorks() {
    let width: CGFloat = 1280, columnWidth: CGFloat = 344, gap: CGFloat = 60, margin: CGFloat = 64
    let panelTop: CGFloat = 158
    let panelHeight = columnWidth * 1080 / 800
    let height = panelTop + panelHeight + 56
    let canvas = Canvas(width: width, height: height)
    canvas.backdrop()

    let steps: [(title: String, detail: String)] = [
        ("Press ⌃⌥P anywhere", "Your prompts appear with search focused. Type a few letters to filter."),
        ("Fill in the blanks", "{{variables}} become a form, with defaults and hints."),
        ("Press ↩, then paste", "The finished prompt is on your clipboard, ready for any AI chat."),
    ]
    for (index, step) in steps.enumerated() {
        let x = margin + CGFloat(index) * (columnWidth + gap)
        canvas.stepBadge(index + 1, at: CGPoint(x: x, y: 50))
        canvas.text(step.title, at: CGPoint(x: x + 46, y: 51), font: .systemFont(ofSize: 25, weight: .bold), color: ink)
        canvas.text(step.detail, at: CGPoint(x: x, y: 98), font: .systemFont(ofSize: 17, weight: .regular), color: muted,
                    width: columnWidth, lineSpacing: 2)
        if index < steps.count - 1 {
            canvas.arrow(centeredAt: CGPoint(x: x + columnWidth + gap / 2, y: panelTop + panelHeight / 2))
        }
    }

    let panelSize = CGSize(width: columnWidth, height: panelHeight)
    canvas.panel(snapshot("popover-list-light"), in: CGRect(origin: CGPoint(x: margin, y: panelTop), size: panelSize))
    canvas.panel(snapshot("popover-fill-light"), in: CGRect(origin: CGPoint(x: margin + columnWidth + gap, y: panelTop), size: panelSize))

    // Step 3 is an illustration of the result, not an app screen.
    let card = CGRect(origin: CGPoint(x: margin + 2 * (columnWidth + gap), y: panelTop), size: panelSize)
    let cardPath = canvas.rounded(card, 14)
    canvas.context.saveGState()
    canvas.setShadow(down: 12, blur: 34, color: rgb(0.12, 0.08, 0.35, 0.20))
    canvas.fill(cardPath, .white)
    canvas.context.restoreGState()
    canvas.stroke(cardPath, rgb(0, 0, 0, 0.12), width: 0.75)

    let check = CGRect(x: card.minX + 22, y: card.minY + 22, width: 26, height: 26)
    canvas.fill(CGPath(ellipseIn: check, transform: nil), rgb(0.20, 0.72, 0.38))
    let tick = CGMutablePath()
    tick.move(to: CGPoint(x: check.minX + 7.5, y: check.midY + 0.5))
    tick.addLine(to: CGPoint(x: check.minX + 11.5, y: check.midY + 4.5))
    tick.addLine(to: CGPoint(x: check.minX + 18.5, y: check.midY - 4.5))
    canvas.context.setLineCap(.round)
    canvas.context.setLineJoin(.round)
    canvas.stroke(tick, .white, width: 2.6)
    canvas.text("Copied to clipboard", at: CGPoint(x: check.maxX + 10, y: card.minY + 23),
                font: .systemFont(ofSize: 18, weight: .semibold), color: ink)
    let divider = CGMutablePath()
    divider.move(to: CGPoint(x: card.minX, y: card.minY + 70))
    divider.addLine(to: CGPoint(x: card.maxX, y: card.minY + 70))
    canvas.stroke(divider, rgb(0, 0, 0, 0.08), width: 1)

    let body = NSFont.systemFont(ofSize: 15.5, weight: .regular)
    let filled = NSFont.systemFont(ofSize: 15.5, weight: .semibold)
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 3.5
    let prompt = NSMutableAttributedString()
    func add(_ string: String, value: Bool = false) {
        prompt.append(NSAttributedString(string: string, attributes: [
            .font: value ? filled : body,
            .foregroundColor: value ? indigo : ink,
            .backgroundColor: value ? rgb(0.33, 0.36, 0.93, 0.10) : NSColor.clear,
            .paragraphStyle: style,
        ]))
    }
    add("You are an expert ")
    add("senior software architect", value: true)
    add(". Help me build a ")
    add("menu bar utility", value: true)
    add(" application using ")
    add("Swift and SwiftUI", value: true)
    add(".\n\nStart by asking me up to five clarifying questions. Then propose:\n1. A high-level architecture\n2. The key data models\n3. A step-by-step implementation plan with milestones")
    canvas.text(prompt, at: CGPoint(x: card.minX + 22, y: card.minY + 90), width: card.width - 44)

    let pasteFont = NSFont.systemFont(ofSize: 16, weight: .medium)
    let pasteLabel = "Paste anywhere"
    let keyHeight: CGFloat = 34
    let rowWidth = canvas.textWidth(pasteLabel, font: pasteFont) + 12 + keyHeight * 2 + 8
    var x = card.midX - rowWidth / 2
    let rowTop = card.maxY - 26 - keyHeight
    canvas.text(pasteLabel, at: CGPoint(x: x, y: rowTop + 7), font: pasteFont, color: muted)
    x += canvas.textWidth(pasteLabel, font: pasteFont) + 12
    x += canvas.keycap("⌘", at: CGPoint(x: x, y: rowTop), height: keyHeight, style: .onLight) + 8
    canvas.keycap("V", at: CGPoint(x: x, y: rowTop), height: keyHeight, style: .onLight)

    canvas.write("how-it-works.png")
}

// MARK: - Feature screenshots

/// Screens side by side on the soft backdrop.
func makePair(_ names: [String], output: String) {
    let images = names.map(snapshot)
    let margin: CGFloat = 52, gap: CGFloat = 44
    let sizes = images.map { pointSize($0) }
    let width = margin * 2 + sizes.map(\.width).reduce(0, +) + gap * CGFloat(images.count - 1)
    let height = margin * 2 + sizes.map(\.height).max()!
    let canvas = Canvas(width: width, height: height)
    canvas.backdrop()
    var x = margin
    for (image, size) in zip(images, sizes) {
        canvas.panel(image, in: CGRect(origin: CGPoint(x: x, y: margin), size: size))
        x += size.width + gap
    }
    canvas.write(output)
}

/// A library window capture with the sidebar column removed. Offscreen rendering can't draw the
/// sidebar's vibrancy, so it comes out blank; cropping is more honest than showing an empty pane.
func makeLibraryShot(_ name: String, sidebarPixels: Int, output: String) {
    let image = crop(snapshot(name), left: sidebarPixels)
    let margin: CGFloat = 48
    let size = pointSize(image)
    let canvas = Canvas(width: size.width + margin * 2, height: size.height + margin * 2)
    canvas.backdrop()
    canvas.panel(image, in: CGRect(origin: CGPoint(x: margin, y: margin), size: size), radius: 12)
    canvas.write(output)
}

makeBanner()
makeBanner(height: 640, dy: 104, popoverTop: 96, maxPixelWidth: 1280, cornerRadius: 0, output: "social-preview.png")
makeHowItWorks()
makePair(["popover-list-dark", "popover-preview-light"], output: "popover.png")
makePair(["popover-edit-light", "popover-fill-dark"], output: "variables.png")
makeLibraryShot("library-editor", sidebarPixels: 442, output: "library.png")
makeLibraryShot("library-history", sidebarPixels: 442, output: "history.png")
