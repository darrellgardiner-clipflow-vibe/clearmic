import AppKit
import SwiftUI

@main
struct RenderUI {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
        for (width, height) in [(1080.0, 850.0), (820.0, 1200.0), (600.0, 1600.0), (420.0, 2000.0), (320.0, 2400.0)] {
            let view = ContentView(session: Session.shared).environment(\.colorScheme, scheme).frame(width: width, height: height)
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            window.contentView = host
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            host.displayIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                fatalError("Could not allocate UI bitmap")
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                fatalError("Could not render ClearMic at width \(width)")
            }
            let path = destination.appendingPathComponent("clearmic-\(Int(width))-\(scheme == .dark ? "dark" : "light").png")
            try png.write(to: path)
            print(path.path)
            window.close()
        }
        }
    }
}
