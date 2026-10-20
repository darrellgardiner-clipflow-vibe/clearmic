import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Session.shared.stop() }
    }
}

@main
struct ClearMicApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var session = Session.shared
    @StateObject private var updater = AppUpdater.shared

    var body: some Scene {
        WindowGroup("ClearMic", id: "main") {
            ContentView(session: session)
                .frame(minWidth: 320, minHeight: 520)
        }
        .defaultSize(width: 1080, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.check() }.disabled(!updater.canCheck)
            }
        }
        MenuBarExtra("ClearMic", systemImage: session.running ? "waveform.circle.fill" : "mic.circle") {
            MenuContent(session: session)
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var session: Session
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Text(session.running ? "ClearMic is processing" : "ClearMic is stopped")
        Toggle("Mute microphone", isOn: $session.settings.muted)
        Toggle("Bypass effects", isOn: $session.settings.bypass)
        Button(session.running ? "Stop processing" : "Start processing") {
            if session.running { session.stop() } else { Task { await session.start() } }
        }
        .disabled(!session.running && !session.canStart)
        Divider()
        Button("Check for Updates…") { AppUpdater.shared.check() }
        Button("Open ClearMic") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Quit ClearMic") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
