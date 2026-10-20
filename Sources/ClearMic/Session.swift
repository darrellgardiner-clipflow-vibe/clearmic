import AVFoundation
import AppKit
import ClearMicAudio
import Combine
import CoreAudio
import Foundation
import OSLog

struct VoiceSettings: Codable, Equatable {
    var sourceUID = ""
    var channel = 0
    var inputGain = 0.0
    var highPass = 80.0
    var bass = 0.0
    var air = 0.0
    var mud = -3.0
    var presence = 2.0
    var threshold = -18.0
    var ratio = 3.0
    var makeup = 0.0
    var deEss = 0.0
    var reverb = 0.0
    var noiseReduction = true
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
                   compressionEnabled: compression ? 1 : 0, monitorGainDB: Float(monitorGain), noiseReductionEnabled: noiseReduction ? 1 : 0, bassGainDB: Float(bass), airGainDB: Float(air), deEssAmount: Float(deEss / 100), reverbMix: Float(reverb / 100))
    }

    var presetSettings: VoiceSettings {
        var value = self
        value.sourceUID = ""; value.channel = 0
        value.monitorUID = ""; value.monitoring = false; value.monitorGain = -18
        value.bypass = false; value.muted = false
        return value
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

struct VoicePreset: Codable, Identifiable {
    let id: String
    var name: String
    var settings: VoiceSettings
}

@MainActor
final class Session: ObservableObject {
    static let shared = Session()
    @Published var settings: VoiceSettings {
        didSet {
            if oldValue.presetSettings != settings.presetSettings { selectedPresetID = "" }
            if let encoded = try? JSONEncoder().encode(settings) { defaults.set(encoded, forKey: "voiceSettings") }
            let inputChanged = oldValue.sourceUID != settings.sourceUID || oldValue.channel != settings.channel
            let outputChanged = oldValue.monitorUID != settings.monitorUID || oldValue.monitoring != settings.monitoring
            if inputChanged || outputChanged {
                let resume = running || starting || restartPending || (outputChanged && settings.monitoring)
                stop()
                let generation = routeGeneration
                if resume {
                    restartPending = true
                    Task {
                        guard generation == routeGeneration else { return }
                        restartPending = false
                        await start()
                    }
                }
            } else { route?.update(settings.controls) }
        }
    }
    @Published private(set) var presets: [VoicePreset] = []
    @Published private(set) var selectedPresetID = ""
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var outputs: [AudioDevice] = []
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var sourceLost = false
    @Published private(set) var driverInstalled = false
    @Published private(set) var driverOnDisk = false
    @Published private(set) var message: String?
    @Published private(set) var virtualMicName = "ClearMic"
    @Published private(set) var inputDB: Float = -120
    @Published private(set) var outputDB: Float = -120
    @Published private(set) var reductionDB: Float = 0
    private var restartPending = false
    private var routeGeneration = 0
    private var route: AudioRouting?
    private let defaults: UserDefaults
    private let listDevices: () -> [AudioDevice]
    private let permission: () async -> Bool
    private let makeRoute: (AudioDevice, Int, AudioDevice?, CMControls) throws -> AudioRouting
    private var timer: Timer?
    private var ticks = 0
    private var lastFrameCount: UInt64 = 0
    private var stalledTicks = 0
    private let logger = Logger(subsystem: "org.clearmic.app", category: "Audio")

    var selectedDevice: AudioDevice? { devices.first { $0.uid == settings.sourceUID } }
    var selectedMonitor: AudioDevice? { outputs.first { $0.uid == settings.monitorUID } }
    var canStart: Bool { selectedDevice != nil && !starting }
    var listening: Bool { running && route?.monitorID != nil }

    init(defaults: UserDefaults = .standard,
         listDevices: @escaping () -> [AudioDevice] = AudioHardware.devices,
         permission: @escaping () async -> Bool = Session.microphonePermission,
         makeRoute: @escaping (AudioDevice, Int, AudioDevice?, CMControls) throws -> AudioRouting = {
             try AudioRoute(source: $0, channel: $1, monitor: $2, controls: $3)
         }, pollDevices: Bool = true) {
        self.defaults = defaults
        self.listDevices = listDevices
        self.permission = permission
        self.makeRoute = makeRoute
        settings = VoiceSettings.load(defaults.data(forKey: "voiceSettings"))
        if let data = defaults.data(forKey: "voicePresets"),
           let stored = try? JSONDecoder().decode([VoicePreset].self, from: data) {
            presets = stored
        }
        refreshDevices()
        if pollDevices {
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.pollAudio() }
            }
        }
    }

    nonisolated static func microphonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func refreshDevices() {
        let previousSourceName = selectedDevice?.name ?? "Selected microphone"
        let all = listDevices()
        let listed = all.filter {
            $0.inputChannels > 0 && $0.uid != AudioHardware.microphoneUID && !$0.uid.hasPrefix("org.clearmic.route.")
        }
        if listed != devices { devices = listed }
        let destinations = all.filter { $0.outputChannels > 0 && !$0.uid.hasPrefix("org.clearmic.route.") && $0.uid != AudioHardware.sendUID }
        if outputs != destinations { outputs = destinations }
        let virtualInput = AudioHardware.resolve(AudioHardware.microphoneUID)
        driverInstalled = virtualInput != nil && AudioHardware.resolve(AudioHardware.sendUID) != nil
        if let virtualInput, let name = AudioHardware.string(virtualInput, kAudioObjectPropertyName) { virtualMicName = name }
        driverOnDisk = FileManager.default.fileExists(atPath: "/Library/Audio/Plug-Ins/HAL/ClearMic.driver")
        if running {
            let sourceChanged = selectedDevice?.id != route?.sourceID || selectedDevice?.sampleRate != 48000
            let monitorChanged = settings.monitoring && selectedMonitor?.id != route?.monitorID
            if sourceChanged || monitorChanged {
                stop()
                sourceLost = sourceChanged
                message = sourceChanged
                    ? "Source lost: \(previousSourceName). Reconnect the microphone, then choose Reconnect."
                    : "Headphone output disconnected. Choose an available output and start again."
            }
        }
    }

    func reconnectSource() async {
        refreshDevices()
        guard selectedDevice != nil else {
            sourceLost = true
            message = "Source is still unavailable. Reconnect the saved microphone and try again, or choose another source."
            return
        }
        await start()
    }

    func selectSource(_ uid: String) {
        guard settings.sourceUID != uid else { return }
        sourceLost = false
        var next = settings
        next.sourceUID = uid
        next.channel = 0
        settings = next
    }

    func start() async {
        guard !running && !starting else { return }
        starting = true
        let generation = routeGeneration
        defer { if generation == routeGeneration { starting = false } }
        let permitted = await permission()
        guard generation == routeGeneration else { return }
        guard permitted else {
            message = "Allow ClearMic in System Settings → Privacy & Security → Microphone."
            return
        }
        refreshDevices()
        guard let source = selectedDevice else {
            sourceLost = !settings.sourceUID.isEmpty
            message = sourceLost ? "Source lost. Reconnect the saved microphone, then choose Reconnect." : "Choose an available microphone first."
            return
        }
        do {
            if settings.monitoring && selectedMonitor == nil { throw RouteError("Choose your headphone output first.") }
            route = try makeRoute(source, settings.channel, settings.monitoring ? selectedMonitor : nil, settings.controls)
            running = true
            sourceLost = false
            lastFrameCount = 0; stalledTicks = 0
            message = nil
            logger.notice("Audio capture started; monitoring=\(self.listening), virtualMic=\(self.driverInstalled)")
        } catch {
            message = error.localizedDescription
            logger.error("Audio route failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        routeGeneration += 1
        restartPending = false
        starting = false
        route?.stop(); route = nil
        running = false
        inputDB = -120; outputDB = -120; reductionDB = 0
        message = nil
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
            process.arguments = ["-e", "do shell script \"/usr/bin/killall coreaudiod\" with administrator privileges"]
            let errors = Pipe(); process.standardError = errors
            do {
                try process.run()
                process.waitUntilExit()
                let errorData = errors.fileHandleForReading.readDataToEndOfFile()
                let detail = String(data: errorData, encoding: .utf8) ?? ""
                await MainActor.run {
                    self.refreshDevices()
                    if process.terminationStatus == 0 {
                        self.message = self.driverInstalled
                            ? nil
                            : "Audio restart requested. Wait a few seconds, then Start. If ClearMic stays unavailable, restart your Mac once."
                    } else {
                        self.message = "Audio reload did not complete. Restart your Mac once to load the installed microphone. No reinstall or security changes are needed. \(detail)"
                    }
                }
            } catch {
                await MainActor.run { self.message = error.localizedDescription }
            }
        }
    }

    func savePreset(name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !name.isEmpty else { return }
        if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            presets[index].settings = settings.presetSettings
            selectedPresetID = presets[index].id
        } else {
            let preset = VoicePreset(id: UUID().uuidString, name: name, settings: settings.presetSettings)
            presets.append(preset)
            selectedPresetID = preset.id
        }
        if let data = try? JSONEncoder().encode(presets) { defaults.set(data, forKey: "voicePresets") }
    }

    func applyPreset(_ id: String) {
        guard let preset = presets.first(where: { $0.id == id }) else { return }
        var next = preset.settings
        next.sourceUID = settings.sourceUID; next.channel = settings.channel
        next.monitorUID = settings.monitorUID; next.monitoring = settings.monitoring
        next.monitorGain = settings.monitorGain
        next.bypass = settings.bypass; next.muted = settings.muted
        settings = next
        selectedPresetID = id
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
        preset.deEss = 0; preset.reverb = 0
        preset.bass = 0; preset.air = 0
        preset.inputGain = 0; preset.highPass = 0; preset.mud = 0; preset.presence = 0
        preset.noiseReduction = false
        preset.compression = false; preset.makeup = 0; preset.bypass = false
        settings = preset
    }

    func pollAudio() {
        ticks += 1
        if ticks % 20 == 0 { refreshDevices() }
        if let values = route?.meters() {
            // Decay the displayed peak instead of making quiet speech unreadable.
            inputDB = max(values.inputPeakDB, inputDB - 3)
            outputDB = max(values.outputPeakDB, outputDB - 3)
            reductionDB = values.reductionDB
            stalledTicks = values.processedFrames == lastFrameCount ? stalledTicks + 1 : 0
            lastFrameCount = values.processedFrames
            if stalledTicks > 30 {
                stop()
                sourceLost = true
                message = "Source stream lost. Choose Reconnect to reopen the saved microphone."
            }
        }
    }
}
