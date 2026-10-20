import AppKit
// Original ClearMic artwork, generated at build time; no upstream branding.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        NSColor(calibratedRed: 0.10, green: 0.16, blue: 0.18, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 210, yRadius: 210).fill()
        NSColor(calibratedRed: 0.55, green: 0.93, blue: 0.75, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 384, y: 370, width: 256, height: 430), xRadius: 128, yRadius: 128).fill()
        NSColor.white.setStroke()
        let stand = NSBezierPath(); stand.lineWidth = 48; stand.lineCapStyle = .round
        stand.move(to: NSPoint(x: 280, y: 520)); stand.line(to: NSPoint(x: 280, y: 440))
        stand.curve(to: NSPoint(x: 744, y: 440), controlPoint1: NSPoint(x: 280, y: 140), controlPoint2: NSPoint(x: 744, y: 140))
        stand.line(to: NSPoint(x: 744, y: 520)); stand.stroke()
        let base = NSBezierPath(); base.lineWidth = 48; base.lineCapStyle = .round
        base.move(to: NSPoint(x: 512, y: 215)); base.line(to: NSPoint(x: 512, y: 130))
        base.move(to: NSPoint(x: 390, y: 130)); base.line(to: NSPoint(x: 634, y: 130)); base.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
