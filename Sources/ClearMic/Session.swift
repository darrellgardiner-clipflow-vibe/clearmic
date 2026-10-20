import AVFoundation
import AppKit
import ClearMicAudio
import Combine
import Foundation

struct VoiceSettings: Codable, Equatable {
    var sourceUID = ""
    var channel = 0
    var inputGain = 0.0
    var highPass = 80.0
    var mud = -3.0
    var presence = 2.0
    var threshold = -18.0
    var ratio = 3.0
    var makeup = 0.0
    var compression = true
    var bypass = false
    var muted = false
    var monitorUID = ""
    var monitoring = false
    var monitorGain = -18.0

    var controls: CMControls {
        CMControls(inputGainDB: Float(inputGain), highPassHz: Float(highPass), mudGainDB: Float(mud),
                   presenceGainDB: Float(presence), thresholdDB: Float(threshold), ratio: Float(ratio),
                   makeupDB: Float(makeup), bypass: bypass ? 1 : 0, muted: muted ? 1 : 0,
                   compressionEnabled: compression ? 1 : 0, monitorGainDB: Float(monitorGain))
    }

    static func load(_ data: Data?) -> VoiceSettings {
        guard let data,
              let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(VoiceSettings()),
              var merged = (try? JSONSerialization.jsonObject(with: defaultsData)) as? [String: Any] else { return VoiceSettings() }
        merged.merge(saved) { _, saved in saved }
        guard let encoded = try? JSONSerialization.data(withJSONObject: merged),
              var settings = try? JSONDecoder().decode(VoiceSettings.self, from: encoded) else { return VoiceSettings() }
        settings.monitoring = false
        return settings
    }
}

@MainActor
final class Session: ObservableObject {
    static let shared = Session()
    @Published var settings: VoiceSettings {
        didSet {
            if let encoded = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(encoded, forKey: "voiceSettings") }
            if oldValue.sourceUID != settings.sourceUID || oldValue.channel != settings.channel {
                stop()
            } else if oldValue.monitorUID != settings.monitorUID || oldValue.monitoring != settings.monitoring {
                let resume = running
                stop()
                if resume { Task { await start() } }
            } else { route?.update(settings.controls) }
        }
    }
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var outputs: [AudioDevice] = []
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var driverInstalled = false
    @Published private(set) var driverOnDisk = false
    @Published private(set) var message = "Choose your microphone, then start processing."
    @Published private(set) var inputDB: Float = -120
    @Published private(set) var outputDB: Float = -120
    @Published private(set) var reductionDB: Float = 0
    private var route: AudioRoute?
    private var timer: Timer?
    private var ticks = 0
    private var lastFrameCount: UInt64 = 0
    private var stalledTicks = 0

    var selectedDevice: AudioDevice? { devices.first { $0.uid == settings.sourceUID } }
    var selectedMonitor: AudioDevice? { outputs.first { $0.uid == settings.monitorUID } }
    var canStart: Bool { (driverInstalled || (settings.monitoring && selectedMonitor != nil)) && selectedDevice != nil && !starting }

    private init() {
        settings = VoiceSettings.load(UserDefaults.standard.data(forKey: "voiceSettings"))
        refreshDevices()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func refreshDevices() {
        let all = AudioHardware.devices()
        let listed = all.filter {
            $0.inputChannels > 0 && $0.uid != AudioHardware.microphoneUID && !$0.uid.hasPrefix("org.clearmic.route.")
        }
        if listed != devices { devices = listed }
        let destinations = all.filter { $0.outputChannels > 0 && !$0.uid.hasPrefix("org.clearmic.route.") && $0.uid != AudioHardware.sendUID }
        if outputs != destinations { outputs = destinations }
        driverInstalled = AudioHardware.resolve(AudioHardware.microphoneUID) != nil && AudioHardware.resolve(AudioHardware.sendUID) != nil
        driverOnDisk = FileManager.default.fileExists(atPath: "/Library/Audio/Plug-Ins/HAL/ClearMic.driver")
        if running, selectedDevice?.id != route?.sourceID || selectedDevice?.sampleRate != 48000 ||
            (settings.monitoring && selectedMonitor?.id != route?.monitorID) {
            stop()
            message = "The audio device changed or disconnected. Check your input and start again."
        }
    }

    func start() async {
        guard !running && !starting else { return }
        starting = true
        defer { starting = false }
        let permitted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: permitted = true
        case .notDetermined: permitted = await AVCaptureDevice.requestAccess(for: .audio)
        default: permitted = false
        }
        guard permitted else {
            message = "Allow ClearMic in System Settings → Privacy & Security → Microphone."
            return
        }
        refreshDevices()
        guard let source = selectedDevice else { message = "Choose an available microphone first."; return }
        do {
            if settings.monitoring && selectedMonitor == nil { throw RouteError("Choose your headphone output first.") }
            route = try AudioRoute(source: source, channel: settings.channel,
                                   monitor: settings.monitoring ? selectedMonitor : nil, controls: settings.controls)
            running = true
            lastFrameCount = 0; stalledTicks = 0
            message = driverInstalled ? "Select ClearMic as the microphone in Riverside or your call app." : "Monitoring only. Install the virtual microphone to send this sound to Riverside."
        } catch { message = error.localizedDescription }
    }

    func stop() {
        route?.stop(); route = nil
        running = false
        inputDB = -120; outputDB = -120; reductionDB = 0
        message = "Processing is stopped. ClearMic sends silence."
    }

    func installDriver() {
        guard let installer = Bundle.main.url(forResource: "ClearMicDriver", withExtension: "pkg") else {
            message = "This build has no driver installer. Build the app with scripts/build-app.sh."
            return
        }
        NSWorkspace.shared.open(installer)
        message = "Complete the macOS installer, then choose Load microphone. Loading briefly interrupts audio."
    }

    func reloadAudioService() {
        stop()
        message = "macOS will request administrator authentication to reload audio. This briefly interrupts all audio."
        Task.detached { [self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "do shell script \"/bin/launchctl kickstart -k system/com.apple.audio.coreaudiod\" with administrator privileges"]
            let errors = Pipe(); process.standardError = errors
            do {
                try process.run()
                process.waitUntilExit()
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                let detail = String(data: errorData, encoding: .utf8) ?? ""
                await MainActor.run {
                    self.refreshDevices()
                    self.message = process.terminationStatus == 0 ? "Audio service reloaded. Choose your input and start processing." : "Audio reload did not complete. \(detail)"
                }
            } catch {
                await MainActor.run { self.message = error.localizedDescription }
            }
        }
    }

    func applyNatural() {
        var preset = VoiceSettings()
        preset.sourceUID = settings.sourceUID; preset.channel = settings.channel
        preset.muted = settings.muted
        preset.monitorUID = settings.monitorUID; preset.monitoring = settings.monitoring; preset.monitorGain = settings.monitorGain
        settings = preset
    }

    func applyFlat() {
        var preset = settings
        preset.inputGain = 0; preset.highPass = 0; preset.mud = 0; preset.presence = 0
        preset.compression = false; preset.makeup = 0; preset.bypass = false
        settings = preset
    }

    private func tick() {
        ticks += 1
        if ticks % 20 == 0 { refreshDevices() }
        if let values = route?.meters() {
            // Decay the displayed peak instead of making quiet speech unreadable.
            inputDB = max(values.inputPeakDB, inputDB - 3)
            outputDB = max(values.outputPeakDB, outputDB - 3)
            reductionDB = values.reductionDB
            stalledTicks = values.processedFrames == lastFrameCount ? stalledTicks + 1 : 0
            lastFrameCount = values.processedFrames
            if values.routingErrors > 0 || stalledTicks > 30 {
                stop()
                message = "The audio stream stopped delivering valid buffers. Check the interface and start again."
            }
        }
    }
}
