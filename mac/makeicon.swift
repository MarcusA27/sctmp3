import AppKit

// sctmp3 icon: a large orange cloud with a glowing halo + white down-arrow,
// on a dark charcoal tile that matches the app.

func symbol(_ name: String, pointSize: CGFloat, color: NSColor, weight: NSFont.Weight) -> NSImage {
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        .withSymbolConfiguration(cfg)!
}

/// Cloud symbol filled with a vertical orange gradient (brighter up top) for volume.
func gradientCloud(size s: NSSize, pointSize: CGFloat) -> NSImage {
    let base = symbol("cloud.fill", pointSize: pointSize, color: .black, weight: .medium)
    let im = NSImage(size: s)
    im.lockFocus()
    let b = NSRect(origin: .zero, size: s)
    base.draw(in: b)
    NSGraphicsContext.current!.compositingOperation = .sourceAtop
    NSGradient(starting: NSColor(srgbRed: 1.0, green: 0.56, blue: 0.27, alpha: 1),
               ending: NSColor(srgbRed: 0.96, green: 0.30, blue: 0.02, alpha: 1))!
        .draw(in: b, angle: -90)
    im.unlockFocus()
    return im
}

func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let orange = NSColor(srgbRed: 1.0, green: 0.36, blue: 0.0, alpha: 1)

    // Dark rounded tile, clipped.
    let corner = size * 0.2237
    let tile = CGRect(x: 0, y: 0, width: size, height: size)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.clip()

    // Cloud geometry (needed early so the background can be lit around it).
    let probe = symbol("cloud.fill", pointSize: size * 0.5, color: .black, weight: .medium)
    let aspect = probe.size.height / probe.size.width
    let w = size * 0.72
    let h = w * aspect
    let rect = NSRect(x: (size - w) / 2, y: (size - h) / 2 + size * 0.02, width: w, height: h)
    let cloud = gradientCloud(size: rect.size, pointSize: size * 0.5)
    let cloudCenter = CGPoint(x: rect.midX, y: rect.midY)

    // Warm-ember radial base: dark amber pulled tight around the cloud, near-black corners.
    let base = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor(srgbRed: 0.125, green: 0.066, blue: 0.032, alpha: 1).cgColor,
                                   NSColor(srgbRed: 0.018, green: 0.016, blue: 0.02, alpha: 1).cgColor] as CFArray,
                          locations: [0, 1])!
    ctx.drawRadialGradient(base, startCenter: cloudCenter, startRadius: 0,
                           endCenter: cloudCenter, endRadius: size * 0.72,
                           options: [.drawsAfterEndLocation])

    // Warm ambient bloom — the cloud's light spilling into the background (additive).
    ctx.setBlendMode(.plusLighter)
    let bloom = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [orange.withAlphaComponent(0.30).cgColor,
                                    orange.withAlphaComponent(0).cgColor] as CFArray,
                           locations: [0, 1])!
    ctx.drawRadialGradient(bloom, startCenter: cloudCenter, startRadius: size * 0.04,
                           endCenter: cloudCenter, endRadius: size * 0.46, options: [])

    // Halo — three additive passes, wide → tight, for a strong glow.
    ctx.setShadow(offset: .zero, blur: size * 0.14, color: orange.withAlphaComponent(0.45).cgColor)
    cloud.draw(in: rect)
    ctx.setShadow(offset: .zero, blur: size * 0.075, color: orange.withAlphaComponent(0.7).cgColor)
    cloud.draw(in: rect)
    ctx.setShadow(offset: .zero, blur: size * 0.035, color: orange.withAlphaComponent(0.95).cgColor)
    cloud.draw(in: rect)
    ctx.setBlendMode(.normal)

    // Crisp cloud on top.
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    cloud.draw(in: rect)

    // White down-arrow with a subtle drop shadow.
    let arrow = symbol("arrow.down", pointSize: size * 0.24, color: .white, weight: .heavy)
    let ar = NSRect(x: (size - arrow.size.width) / 2,
                    y: rect.midY - arrow.size.height / 2,
                    width: arrow.size.width, height: arrow.size.height)
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.008), blur: size * 0.012,
                  color: NSColor(srgbRed: 0.5, green: 0.12, blue: 0, alpha: 0.4).cgColor)
    arrow.draw(in: ar)

    ctx.restoreGState()
    img.unlockFocus()
    return img
}

func writePNG(_ image: NSImage, to path: String, px: Int) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

let outDir = CommandLine.arguments[1]
let sizes = [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
             (128, "128x128"), (256, "128x128@2x"), (256, "256x256"),
             (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")]
for (px, name) in sizes {
    let img = drawIcon(size: CGFloat(px))
    writePNG(img, to: "\(outDir)/icon_\(name).png", px: px)
}
print("icons written")
