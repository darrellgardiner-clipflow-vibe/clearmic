import AppKit

// Original ClearMic recessed C and right-facing microphone capsule. All geometry lives in a 1024-point canvas.
// White space, a continuous tile contour and shallow edge relief keep the mark
// legible in the Dock. Generate each representation directly from the paths.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}

func tilePath() -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 302, y: 920))
    p.line(to: NSPoint(x: 722, y: 920))
    p.curve(to: NSPoint(x: 920, y: 722), controlPoint1: NSPoint(x: 862, y: 920), controlPoint2: NSPoint(x: 920, y: 862))
    p.line(to: NSPoint(x: 920, y: 302))
    p.curve(to: NSPoint(x: 722, y: 104), controlPoint1: NSPoint(x: 920, y: 162), controlPoint2: NSPoint(x: 862, y: 104))
    p.line(to: NSPoint(x: 302, y: 104))
    p.curve(to: NSPoint(x: 104, y: 302), controlPoint1: NSPoint(x: 162, y: 104), controlPoint2: NSPoint(x: 104, y: 162))
    p.line(to: NSPoint(x: 104, y: 722))
    p.curve(to: NSPoint(x: 302, y: 920), controlPoint1: NSPoint(x: 104, y: 862), controlPoint2: NSPoint(x: 162, y: 920))
    p.close()
    return p
}

func ribbonPath() -> NSBezierPath {
    // An open C with opposing diagonal terminals: one broad, continuous ribbon.
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 732, y: 768))
    p.line(to: NSPoint(x: 504, y: 768))
    p.curve(to: NSPoint(x: 270, y: 534), controlPoint1: NSPoint(x: 352, y: 768), controlPoint2: NSPoint(x: 270, y: 686))
    p.line(to: NSPoint(x: 270, y: 490))
    p.curve(to: NSPoint(x: 504, y: 256), controlPoint1: NSPoint(x: 270, y: 338), controlPoint2: NSPoint(x: 352, y: 256))
    p.line(to: NSPoint(x: 732, y: 256))
    p.curve(to: NSPoint(x: 744, y: 284), controlPoint1: NSPoint(x: 750, y: 256), controlPoint2: NSPoint(x: 756, y: 272))
    p.line(to: NSPoint(x: 626, y: 400))
    p.curve(to: NSPoint(x: 598, y: 412), controlPoint1: NSPoint(x: 618, y: 408), controlPoint2: NSPoint(x: 608, y: 412))
    p.line(to: NSPoint(x: 514, y: 412))
    p.curve(to: NSPoint(x: 426, y: 500), controlPoint1: NSPoint(x: 456, y: 412), controlPoint2: NSPoint(x: 426, y: 442))
    p.line(to: NSPoint(x: 426, y: 524))
    p.curve(to: NSPoint(x: 514, y: 612), controlPoint1: NSPoint(x: 426, y: 582), controlPoint2: NSPoint(x: 456, y: 612))
    p.line(to: NSPoint(x: 598, y: 612))
    p.curve(to: NSPoint(x: 626, y: 624), controlPoint1: NSPoint(x: 608, y: 612), controlPoint2: NSPoint(x: 618, y: 616))
    p.line(to: NSPoint(x: 744, y: 740))
    p.curve(to: NSPoint(x: 732, y: 768), controlPoint1: NSPoint(x: 756, y: 752), controlPoint2: NSPoint(x: 750, y: 768))
    p.close()
    return p
}

func capsulePath() -> NSBezierPath {
    // A small rear connector and rounded grille end establish a right-facing mic.
    // The C remains much heavier and stays separate from this secondary detail.
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 478, y: 526))
    p.line(to: NSPoint(x: 506, y: 526))
    p.curve(to: NSPoint(x: 568, y: 570), controlPoint1: NSPoint(x: 520, y: 556), controlPoint2: NSPoint(x: 538, y: 570))
    p.line(to: NSPoint(x: 692, y: 570))
    p.curve(to: NSPoint(x: 750, y: 512), controlPoint1: NSPoint(x: 728, y: 570), controlPoint2: NSPoint(x: 750, y: 548))
    p.curve(to: NSPoint(x: 692, y: 454), controlPoint1: NSPoint(x: 750, y: 476), controlPoint2: NSPoint(x: 728, y: 454))
    p.line(to: NSPoint(x: 568, y: 454))
    p.curve(to: NSPoint(x: 506, y: 498), controlPoint1: NSPoint(x: 538, y: 454), controlPoint2: NSPoint(x: 520, y: 468))
    p.line(to: NSPoint(x: 478, y: 498))
    p.curve(to: NSPoint(x: 464, y: 512), controlPoint1: NSPoint(x: 469, y: 498), controlPoint2: NSPoint(x: 464, y: 503))
    p.curve(to: NSPoint(x: 478, y: 526), controlPoint1: NSPoint(x: 464, y: 521), controlPoint2: NSPoint(x: 469, y: 526))
    p.close()
    return p
}

func recess(_ path: NSBezierPath, pixels: Int) {
    let scale = CGFloat(pixels) / 1024
    // A pale lip on the white surface; no exterior shadow beneath the colored mark.
    NSGraphicsContext.saveGraphicsState()
    let lip = path.copy() as! NSBezierPath
    let offset = NSAffineTransform(); offset.translateX(by: -1, yBy: -3)
    lip.transform(using: offset as AffineTransform)
    color(1, 1, 1, 0.95).setStroke()
    lip.lineWidth = 4
    lip.stroke()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [color(0.96, 0.17, 0.16), color(1, 0.29, 0.15), color(1, 0.39, 0.22)])!.draw(in: path, angle: 90)
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    // Shadow comes FROM the surrounding white material INTO the colored cavity.
    // The inverse silhouette is clipped out, leaving only its inward shadow.
    let surrounding = NSBezierPath(rect: NSRect(x: -100, y: -100, width: 1224, height: 1224))
    surrounding.append(path)
    surrounding.windingRule = .evenOdd
    let shadow = NSShadow()
    shadow.shadowColor = color(0.32, 0.035, 0.01, 0.65)
    shadow.shadowOffset = NSSize(width: 4 * scale, height: -9 * scale)
    shadow.shadowBlurRadius = 12 * scale
    shadow.set()
    color(0.32, 0.035, 0.01).setFill()
    surrounding.fill()
    NSGraphicsContext.restoreGraphicsState()
}

func drawIcon(pixels: Int) {
    let outputScale = CGFloat(pixels) / 1024
    let tile = tilePath()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0.16, 0.12, 0.10, 0.16)
    shadow.shadowOffset = NSSize(width: 0, height: -8 * outputScale)
    shadow.shadowBlurRadius = 14 * outputScale
    shadow.set()
    color(0.97, 0.965, 0.955).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(1, 1, 0.995), ending: color(0.945, 0.94, 0.925))!.draw(in: tile, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    color(1, 1, 1, 0.9).setStroke()
    tile.lineWidth = 5
    tile.stroke()
    NSGraphicsContext.restoreGraphicsState()

    recess(ribbonPath(), pixels: pixels)
    recess(capsulePath(), pixels: pixels)

    // Grille slots are secondary details. Omit below 64px to preserve the C.
    if pixels >= 64 {
        for (x, height) in [(682.0, 72.0), (702.0, 64.0), (722.0, 42.0)] {
            let slot = NSBezierPath(roundedRect: NSRect(x: x, y: 512 - height / 2, width: 6, height: height), xRadius: 3, yRadius: 3)
            color(1, 0.96, 0.92, 0.90).setFill()
            slot.fill()
        }
    }
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        drawIcon(pixels: pixels)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
