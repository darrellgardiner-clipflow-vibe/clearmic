import AppKit

// Original ClearMic ribbon mark. All geometry lives in a 1024-point canvas.
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

func drawIcon(pixels: Int) {
    let outputScale = CGFloat(pixels) / 1024
    let tile = tilePath()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0.16, 0.12, 0.10, 0.19)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * outputScale)
    shadow.shadowBlurRadius = 18 * outputScale
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

    let mark = ribbonPath()
    NSGraphicsContext.saveGraphicsState()
    let relief = NSShadow()
    relief.shadowColor = color(0.47, 0.08, 0.015, 0.16)
    relief.shadowOffset = NSSize(width: 0, height: -3 * outputScale)
    relief.shadowBlurRadius = 7 * outputScale
    relief.set()
    color(0.98, 0.25, 0.12).setFill()
    mark.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0.94, 0.14, 0.18), color(1, 0.28, 0.16), color(1, 0.40, 0.23)])!.draw(in: mark, angle: 90)

    // Restrained inset rim, omitted at tiny sizes so the silhouette stays clean.
    if pixels >= 64 {
        NSGraphicsContext.saveGraphicsState()
        mark.addClip()
        color(0.56, 0.055, 0.025, 0.25).setStroke()
        mark.lineWidth = 5
        mark.stroke()
        let highlight = mark.copy() as! NSBezierPath
        let offset = NSAffineTransform(); offset.translateX(by: 0, yBy: -3); highlight.transform(using: offset as AffineTransform)
        color(1, 0.85, 0.64, 0.44).setStroke()
        highlight.lineWidth = 2
        highlight.stroke()
        NSGraphicsContext.restoreGraphicsState()
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
