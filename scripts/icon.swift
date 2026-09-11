import AppKit
import Foundation

// Fold's app icon, in three variants, to macOS icon proportions: a rounded
// square occupying ~82% of a square canvas, which is what Finder and the Dock
// expect from a modern .icns.
//
//   swift scripts/icon.swift --variant refined --icns Fold/AppIcon.icns
//   swift scripts/icon.swift --variant refined --preview /tmp/icon.png --size 512
//
// Variants:
//   refined   blue gradient, white folded sheet, the original idea sharpened
//   graphite  dark neutral, single accent line, calmer in a busy Dock
//   hinge     two panels meeting at a visible hinge, the fold made literal

enum Variant: String, CaseIterable {
    case refined, graphite, hinge
}

let arguments = CommandLine.arguments
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.count > index + 1 else { return nil }
    return arguments[index + 1]
}

let variant = Variant(rawValue: option("--variant") ?? "refined") ?? .refined
let canvas: CGFloat = 1024
let margin: CGFloat = 0.09          // macOS style breathing room
let radius: CGFloat = 0.2237        // squircle-ish corner radius (Apple's ratio)

func panel(_ n: CGFloat) -> NSRect {
    let inset = n * margin
    return NSRect(x: inset, y: inset, width: n - inset * 2, height: n - inset * 2)
}

/// The folded sheet: a trapezoid narrowing towards the top, hinged at the base.
func foldedSheet(in rect: NSRect, bottomWidth: CGFloat, topWidth: CGFloat, height: CGFloat) -> NSBezierPath {
    let cx = rect.midX
    let bottomY = rect.minY + rect.height * (0.5 - height / 2)
    let topY = bottomY + rect.height * height
    let path = NSBezierPath()
    path.move(to: NSPoint(x: cx - rect.width * bottomWidth / 2, y: bottomY))
    path.line(to: NSPoint(x: cx + rect.width * bottomWidth / 2, y: bottomY))
    path.line(to: NSPoint(x: cx + rect.width * topWidth / 2, y: topY))
    path.line(to: NSPoint(x: cx - rect.width * topWidth / 2, y: topY))
    path.close()
    return path
}

func roundedPanel(_ rect: NSRect) -> NSBezierPath {
    NSBezierPath(
        roundedRect: rect, xRadius: rect.width * radius / (1 - 2 * margin),
        yRadius: rect.width * radius / (1 - 2 * margin))
}

func draw(_ n: CGFloat) -> CGImage {
    let image = NSImage(size: NSSize(width: n, height: n), flipped: false) { _ in
        let rect = panel(n)
        let panelPath = roundedPanel(rect)

        switch variant {
        case .refined:
            NSGradient(colors: [
                NSColor(srgbRed: 0.07, green: 0.26, blue: 0.72, alpha: 1),
                NSColor(srgbRed: 0.45, green: 0.71, blue: 1.0, alpha: 1),
            ])!.draw(in: panelPath, angle: 68)
        case .graphite:
            NSGradient(colors: [
                NSColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1),
                NSColor(srgbRed: 0.27, green: 0.28, blue: 0.31, alpha: 1),
            ])!.draw(in: panelPath, angle: 68)
        case .hinge:
            NSGradient(colors: [
                NSColor(srgbRed: 0.03, green: 0.13, blue: 0.36, alpha: 1),
                NSColor(srgbRed: 0.32, green: 0.58, blue: 0.95, alpha: 1),
            ])!.draw(in: panelPath, angle: 90)
        }

        // The sheet.
        let sheet = foldedSheet(
            in: rect,
            bottomWidth: variant == .hinge ? 0.68 : 0.58,
            topWidth: variant == .hinge ? 0.42 : 0.34,
            height: variant == .hinge ? 0.46 : 0.42)

        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -n * 0.012)
        shadow.shadowBlurRadius = n * 0.045
        shadow.shadowColor = NSColor.black.withAlphaComponent(variant == .graphite ? 0.55 : 0.35)
        shadow.set()

        switch variant {
        case .refined:
            NSGradient(colors: [
                NSColor(calibratedWhite: 1.0, alpha: 0.99),
                NSColor(calibratedWhite: 0.82, alpha: 0.92),
            ])!.draw(in: sheet, angle: 90)
            sheet.lineWidth = n * 0.018
            NSColor.white.setStroke()
            sheet.stroke()
        case .graphite:
            NSGradient(colors: [
                NSColor(calibratedWhite: 0.97, alpha: 1),
                NSColor(calibratedWhite: 0.74, alpha: 1),
            ])!.draw(in: sheet, angle: 90)
            sheet.lineWidth = n * 0.014
            NSColor(calibratedWhite: 0.99, alpha: 1).setStroke()
            sheet.stroke()
        case .hinge:
            // Upper panel in white, lower panel a translucent sheen: the fold.
            // The lower panel must share the upper panel's bottom width, or the
            // silhouette breaks into three shapes instead of one folded sheet.
            let upper = foldedSheet(in: rect, bottomWidth: 0.68, topWidth: 0.42, height: 0.3)
            NSGradient(colors: [
                NSColor(calibratedWhite: 1.0, alpha: 0.98),
                NSColor(calibratedWhite: 0.85, alpha: 0.95),
            ])!.draw(in: upper, angle: 90)
            upper.lineWidth = n * 0.016
            NSColor.white.setStroke()
            upper.stroke()
            let lower = foldedSheet(in: rect, bottomWidth: 0.68, topWidth: 0.68, height: 0.16)
            NSColor(calibratedWhite: 1.0, alpha: 0.3).setFill()
            lower.fill()
        }
        NSGraphicsContext.current?.cgContext.setShadow(offset: .zero, blur: 0, color: nil)

        // Base / hinge mark, kept clear of the sheet.
        let base = NSBezierPath(
            roundedRect: NSRect(
                x: rect.midX - rect.width * 0.28, y: rect.minY + rect.height * 0.2,
                width: rect.width * 0.56, height: rect.height * 0.035),
            xRadius: rect.height * 0.0175, yRadius: rect.height * 0.0175)
        if variant == .graphite {
            NSColor(srgbRed: 0.04, green: 0.52, blue: 1.0, alpha: 1).setFill()
        } else {
            NSColor.white.setFill()
        }
        base.fill()
        return true
    }
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
}

func writePNG(_ image: CGImage, to path: String, size: CGFloat? = nil) {
    let rep: NSBitmapImageRep
    if let size {
        rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: image, size: NSSize(width: size, height: size)).draw(
            in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
    } else {
        rep = NSBitmapImageRep(cgImage: image)
    }
    try! rep.representation(using: .png, properties: [:])!.write(
        to: URL(fileURLWithPath: path))
}

if let preview = option("--preview") {
    let size = CGFloat(Double(option("--size") ?? "512") ?? 512)
    writePNG(draw(canvas), to: preview, size: size)
    print("wrote \(preview) (\(Int(size))px, variant \(variant.rawValue))")
    exit(0)
}

if let icns = option("--icns") {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
        "FoldAppIcon-\(UUID().uuidString).iconset")
    try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let source = draw(canvas)
    // iconutil wants these exact names.
    let plan: [(String, CGFloat)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]
    for (name, size) in plan {
        writePNG(source, to: folder.appendingPathComponent(name).path, size: size)
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["--convert", "icns", "--output", icns, folder.path]
    try! process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
        exit(1)
    }
    try? FileManager.default.removeItem(at: folder)
    print("wrote \(icns) (variant \(variant.rawValue))")
    exit(0)
}

FileHandle.standardError.write(
    "usage: icon.swift --variant refined|graphite|hinge [--icns path | --preview path [--size N]]\n"
        .data(using: .utf8)!)
exit(2)
