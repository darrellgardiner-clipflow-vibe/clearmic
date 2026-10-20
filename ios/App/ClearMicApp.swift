import RouteCore
import SwiftUI

@main struct ClearMicIOSApp: App {
    @StateObject private var session = MicrophoneSession(hardware: IOSAudioHardware())
    var body: some Scene {
        WindowGroup { MicrophoneView(session: session) }
    }
}
