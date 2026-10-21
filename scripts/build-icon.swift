import AppKit

// Original ClearMic recessed C and right-facing microphone capsule. All geometry lives in a 1024-point canvas.
// White space, a continuous tile contour and shallow edge relief keep the mark
// legible in the Dock. Generate each representation directly from the paths.
let isIOS = CommandLine.arguments.contains("--ios")
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
    // The rear follows the C's inner curve with a 28–30 point white channel.
    // A longer horizontal body and compact nose keep the C visually dominant.
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 514, y: 584))
    p.line(to: NSPoint(x: 678, y: 584))
    p.curve(to: NSPoint(x: 750, y: 512), controlPoint1: NSPoint(x: 718, y: 584), controlPoint2: NSPoint(x: 750, y: 552))
    p.curve(to: NSPoint(x: 678, y: 440), controlPoint1: NSPoint(x: 750, y: 472), controlPoint2: NSPoint(x: 718, y: 440))
    p.line(to: NSPoint(x: 514, y: 440))
    p.curve(to: NSPoint(x: 456, y: 500), controlPoint1: NSPoint(x: 476, y: 440), controlPoint2: NSPoint(x: 456, y: 462))
    p.line(to: NSPoint(x: 456, y: 524))
    p.curve(to: NSPoint(x: 514, y: 584), controlPoint1: NSPoint(x: 456, y: 562), controlPoint2: NSPoint(x: 476, y: 584))
    p.close()
    return p
}

func waveformPath(pixels: Int) -> NSBezierPath {
    // One construction axis, exactly parallel to the C's terminal faces.
    // Wave peaks are laid out in axis/normal coordinates, not freehand points.
    let p = NSBezierPath()
    let terminalLength = hypot(CGFloat(118), CGFloat(116))
    let axis = CGVector(dx: 118 / terminalLength, dy: 116 / terminalLength)
    let origin = NSPoint(x: 604, y: 512)
    let samples: [(CGFloat, CGFloat)] = [
        (-420, 0), (-60, 0), (-30, 26), (0, -30),
        (30, 26), (60, 0), (300, 0)
    ]
    for (index, sample) in samples.enumerated() {
        let (along, across) = sample
        let point = NSPoint(x: origin.x + axis.dx * along - axis.dy * across,
                            y: origin.y + axis.dy * along + axis.dx * across)
        if index == 0 { p.move(to: point) } else { p.line(to: point) }
    }
    p.lineWidth = 34
    p.lineJoinStyle = .round
    p.lineCapStyle = .round
    return p
}

func cutoutPath(pixels: Int) -> NSBezierPath {
    let body = ribbonPath().cgPath.union(capsulePath().cgPath)
    let waveform = waveformPath(pixels: pixels)
    let channel = waveform.cgPath.copy(strokingWithWidth: waveform.lineWidth,
                                      lineCap: .round, lineJoin: .round, miterLimit: 2)
    let cutout = body.subtracting(channel)
    // Inset and restore the silhouette with round joins. This gives the newly
    // exposed corners a 7-point radius before applying the shared inner shadow.
    let radius: CGFloat = 7
    let edge = cutout.copy(strokingWithWidth: radius * 2,
                          lineCap: .round, lineJoin: .round, miterLimit: 2)
    let inset = cutout.subtracting(edge)
    let roundedEdge = inset.copy(strokingWithWidth: radius * 2,
                                 lineCap: .round, lineJoin: .round, miterLimit: 2)
    return NSBezierPath(cgPath: inset.union(roundedEdge))
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
    let tile = isIOS ? NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)) : tilePath()
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0.16, 0.12, 0.10, 0.16)
    shadow.shadowOffset = NSSize(width: 0, height: -8 * outputScale)
    shadow.shadowBlurRadius = 14 * outputScale
    if !isIOS { shadow.set() }
    color(0.97, 0.965, 0.955).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(1, 1, 0.995), ending: color(0.945, 0.94, 0.925))!.draw(in: tile, angle: -90)
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    color(1, 1, 1, 0.9).setStroke()
    tile.lineWidth = 5
    if !isIOS { tile.stroke() }
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    // iOS supplies the outer icon mask; fill its canvas and retain the same
    // mark-to-tile proportions as the macOS artwork.
    if isIOS {
        let fit = NSAffineTransform()
        fit.translateX(by: 512, yBy: 512)
        fit.scale(by: 1024 / 816)
        fit.translateX(by: -512, yBy: -512)
        fit.concat()
    }
    // Optical centering applies to the complete mark, not the white tile.
    let balance = NSAffineTransform()
    balance.translateX(by: -20, yBy: 0)
    balance.concat()
    // Subtract first, then shade every edge of the resulting cavity together.
    recess(cutoutPath(pixels: pixels), pixels: pixels)
    NSGraphicsContext.restoreGraphicsState()
}

let representations: [(Int, String)] = isIOS ? [(1024, "AppIcon.png")] :
    [16, 32, 128, 256, 512].flatMap { size in
        [(size, "icon_\(size)x\(size).png"), (size * 2, "icon_\(size)x\(size)@2x.png")]
    }
for (pixels, filename) in representations {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
    drawIcon(pixels: pixels)
    NSGraphicsContext.restoreGraphicsState()
    let output: NSBitmapImageRep
    if isIOS {
        let opaque = CGContext(data: nil, width: pixels, height: pixels,
                               bitsPerComponent: 8, bytesPerRow: pixels * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        opaque.draw(bitmap.cgImage!, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        output = NSBitmapImageRep(cgImage: opaque.makeImage()!)
    } else { output = bitmap }
    try output.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
}
