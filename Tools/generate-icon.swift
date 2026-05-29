import AppKit

// Generates AppIcon.iconset (a warm flame on a rounded-rect gradient — the colorful
// Dock/app-icon counterpart to the monochrome menu-bar glyph), then build.sh's caller
// turns it into AppIcon.icns. Regenerate with:
//
//   swiftc -o /tmp/genicon Tools/generate-icon.swift && /tmp/genicon
//   iconutil -c icns AppIcon.iconset -o AppIcon.icns

let outDir = FileManager.default.currentDirectoryPath + "/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func whiteVersion(_ image: NSImage) -> NSImage {
    let out = NSImage(size: image.size)
    out.lockFocus()
    image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
    out.unlockFocus()
    return out
}

func renderPNG(px: CGFloat) -> Data {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!
    ctx.imageInterpolation = .high

    // Squircle: large rounded rect with a small transparent margin, plus a soft shadow.
    let margin = px * 0.085
    let rect = NSRect(x: margin, y: margin, width: px - 2 * margin, height: px - 2 * margin)
    let radius = rect.width * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -px * 0.008)
    shadow.shadowBlurRadius = px * 0.03
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Warm fire gradient, top -> bottom.
    let top = NSColor(calibratedRed: 1.00, green: 0.70, blue: 0.24, alpha: 1) // amber
    let bottom = NSColor(calibratedRed: 0.94, green: 0.24, blue: 0.13, alpha: 1) // ember red
    let grad = NSGradient(colors: [top, bottom])!
    grad.draw(in: path, angle: -90)

    // Subtle top sheen for a bit of glassy depth.
    let sheen = NSGradient(colors: [
        NSColor.white.withAlphaComponent(0.22),
        NSColor.white.withAlphaComponent(0.0),
    ])!
    path.addClip()
    sheen.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)
    ctx.cgContext.resetClip()

    // White flame, centered.
    let cfg = NSImage.SymbolConfiguration(pointSize: rect.height * 0.52, weight: .semibold)
    if let flame = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let white = whiteVersion(flame)
        let s = white.size
        white.draw(in: NSRect(x: rect.midX - s.width / 2,
                              y: rect.midY - s.height / 2,
                              width: s.width, height: s.height))
    }

    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let specs: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in specs {
    try! renderPNG(px: px).write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("wrote \(specs.count) icon sizes to \(outDir)")
