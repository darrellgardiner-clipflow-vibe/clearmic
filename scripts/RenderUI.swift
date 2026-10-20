import AppKit
import SwiftUI
import ClearMicAudio

@main
struct RenderUI {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let suite = "ClearMicUIAudit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let mic = AudioDevice(id: 1, uid: "audit-mic", name: "RØDE PodMic USB", inputChannels: 2, outputChannels: 0, sampleRate: 48000)
        let headphones = AudioDevice(id: 2, uid: "audit-headphones", name: "AirPods Pro", inputChannels: 0, outputChannels: 2, sampleRate: 48000)
        let session = Session(defaults: defaults, listDevices: { [mic, headphones] }, permission: { false }, pollDevices: false)
        session.completeOnboarding()
        session.selectSource(mic.uid)
        session.settings.monitorUID = headphones.uid
        session.savePreset(name: "Podcast")
        session.settings.bass = 3
        session.savePreset(name: "Warm voice")
        session.settings.air = 2
        session.savePreset(name: "A very long saved voice profile name for wrap testing")
        session.applyPreset(session.presets[0].id)
        session.settings.bass = 1
        let requestedWidths = CommandLine.arguments.dropFirst(2).compactMap(Double.init)
        let widths = requestedWidths.isEmpty ? [320.0, 379, 380, 391, 392, 439, 440, 539, 540, 663, 664, 739, 740, 787, 788, 1080, 1280] : requestedWidths
        for scheme in [ColorScheme.light, .dark] {
            for width in widths {
                let height = width < 740 ? 2700.0 : 1700.0
                try capture(ContentView(session: session), width: width, height: height, scheme: scheme,
                            path: destination.appendingPathComponent("clearmic-\(Int(width))-\(scheme == .dark ? "dark" : "light").png"))
            }
            for page in 0..<3 {
                try capture(SetupView(session: session, page: page, done: {}), width: 416, height: 430, scheme: scheme,
                            path: destination.appendingPathComponent("setup-\(page + 1)-\(scheme == .dark ? "dark" : "light").png"))
            }
            session.choosePreset(session.presets[0].id)
            for width in [320.0, 1080] {
                try capture(ContentView(session: session), width: width, height: 2700, scheme: scheme,
                            path: destination.appendingPathComponent("confirm-\(Int(width))-\(scheme == .dark ? "dark" : "light").png"))
            }
            session.cancelPresetOverwrite()
        }
    }

    @MainActor static func capture<Content: View>(_ view: Content, width: Double, height: Double, scheme: ColorScheme, path: URL) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme).frame(width: width, height: height))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Could not allocate UI bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render ClearMic at width \(width)") }
        try png.write(to: path)
        print(path.path)
        window.close()
    }
}
