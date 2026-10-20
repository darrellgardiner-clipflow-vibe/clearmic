import AppKit

// Original ClearMic waveform microphone mark. All geometry lives in a 1024-point canvas.
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

func microphonePath() -> NSBezierPath {
    // One continuous outline: capsule, cradle and foot share their actual edges.
    // There are no overlapping pieces to leave seams in the inset rim.
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 512, y: 800))
    p.curve(to: NSPoint(x: 640, y: 672), controlPoint1: NSPoint(x: 590, y: 800), controlPoint2: NSPoint(x: 640, y: 750))
    p.line(to: NSPoint(x: 640, y: 524))
    p.curve(to: NSPoint(x: 544, y: 396), controlPoint1: NSPoint(x: 640, y: 442), controlPoint2: NSPoint(x: 544, y: 430))
    p.line(to: NSPoint(x: 544, y: 358))
    p.curve(to: NSPoint(x: 672, y: 516), controlPoint1: NSPoint(x: 624, y: 370), controlPoint2: NSPoint(x: 672, y: 425))
    p.line(to: NSPoint(x: 672, y: 548))
    p.curve(to: NSPoint(x: 736, y: 548), controlPoint1: NSPoint(x: 672, y: 590), controlPoint2: NSPoint(x: 736, y: 590))
    p.line(to: NSPoint(x: 736, y: 516))
    p.curve(to: NSPoint(x: 554, y: 292), controlPoint1: NSPoint(x: 736, y: 389), controlPoint2: NSPoint(x: 666, y: 309))
    p.line(to: NSPoint(x: 554, y: 270))
    p.curve(to: NSPoint(x: 582, y: 242), controlPoint1: NSPoint(x: 554, y: 251), controlPoint2: NSPoint(x: 563, y: 242))
    p.line(to: NSPoint(x: 612, y: 242))
    p.curve(to: NSPoint(x: 612, y: 194), controlPoint1: NSPoint(x: 644, y: 242), controlPoint2: NSPoint(x: 644, y: 194))
    p.line(to: NSPoint(x: 412, y: 194))
    p.curve(to: NSPoint(x: 412, y: 242), controlPoint1: NSPoint(x: 380, y: 194), controlPoint2: NSPoint(x: 380, y: 242))
    p.line(to: NSPoint(x: 442, y: 242))
    p.curve(to: NSPoint(x: 470, y: 270), controlPoint1: NSPoint(x: 461, y: 242), controlPoint2: NSPoint(x: 470, y: 251))
    p.line(to: NSPoint(x: 470, y: 292))
    p.curve(to: NSPoint(x: 288, y: 516), controlPoint1: NSPoint(x: 358, y: 309), controlPoint2: NSPoint(x: 288, y: 389))
    p.line(to: NSPoint(x: 288, y: 548))
    p.curve(to: NSPoint(x: 352, y: 548), controlPoint1: NSPoint(x: 288, y: 590), controlPoint2: NSPoint(x: 352, y: 590))
    p.line(to: NSPoint(x: 352, y: 516))
    p.curve(to: NSPoint(x: 480, y: 358), controlPoint1: NSPoint(x: 352, y: 425), controlPoint2: NSPoint(x: 400, y: 370))
    p.line(to: NSPoint(x: 480, y: 396))
    p.curve(to: NSPoint(x: 384, y: 524), controlPoint1: NSPoint(x: 480, y: 430), controlPoint2: NSPoint(x: 384, y: 442))
    p.line(to: NSPoint(x: 384, y: 672))
    p.curve(to: NSPoint(x: 512, y: 800), controlPoint1: NSPoint(x: 384, y: 750), controlPoint2: NSPoint(x: 434, y: 800))
    p.close()
    return p
}

func waveformPath(pixels: Int) -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 354, y: 604))
    p.line(to: NSPoint(x: 438, y: 604))
    p.line(to: NSPoint(x: 466, y: 642))
    p.line(to: NSPoint(x: 504, y: 550))
    p.line(to: NSPoint(x: 546, y: 658))
    p.line(to: NSPoint(x: 580, y: 604))
    p.line(to: NSPoint(x: 670, y: 604))
    p.lineJoinStyle = .round
    p.lineCapStyle = .round
    p.lineWidth = pixels <= 32 ? 32 : 24
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

    NSGraphicsContext.saveGraphicsState()
    let tilt = NSAffineTransform()
    tilt.translateX(by: 512, yBy: 504)
    tilt.rotate(byDegrees: -12)
    tilt.translateX(by: -512, yBy: -504)
    tilt.concat()
    let context = NSGraphicsContext.current!.cgContext
    // Isolate the mark: waveform knockout exposes the tile, never the desktop.
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    let mark = microphonePath()
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
    context.setBlendMode(.clear)
    waveformPath(pixels: pixels).stroke()
    context.setBlendMode(.normal)
    context.endTransparencyLayer()
    NSGraphicsContext.restoreGraphicsState()
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
