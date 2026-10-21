import Combine
import Foundation

public struct Microphone: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let bluetooth: Bool
    public init(id: String, name: String, bluetooth: Bool) {
        self.id = id; self.name = name; self.bluetooth = bluetooth
    }
}

public enum AudioEvent: Sendable {
    case routeChanged, interrupted, mediaReset, testFinished
    case testFailed(String)
}

@MainActor public protocol MicrophoneHardware: AnyObject {
    var inputs: [Microphone] { get }
    var activeInput: Microphone? { get }
    var gain: Float? { get }
    var isRecording: Bool { get }
    var onEvent: ((AudioEvent) -> Void)? { get set }
    func requestPermission() async -> Bool
    func activate() throws
    func select(_ id: String) throws
    func setGain(_ value: Float) throws
    func startLevelTest(duration: TimeInterval) throws
    func peak() -> Float
    func stopLevelTest()
    func deactivate() throws
}

public enum MicrophoneState: Equatable {
    case idle, preparing, ready, testing, cameraHandoff, cameraReleased, interrupted, sourceLost
    case failed(String)

    public var title: String {
        switch self {
        case .idle: return "Connect a microphone"
        case .preparing: return "Checking input"
        case .ready: return "Input ready"
        case .testing: return "Testing microphone"
        case .cameraHandoff: return "Microphone active for Camera"
        case .cameraReleased: return "ClearMic capture ended"
        case .interrupted: return "Audio session interrupted"
        case .sourceLost: return "Selected microphone lost"
        case .failed: return "Input unavailable"
        }
    }
}

@MainActor public final class MicrophoneSession: ObservableObject {
    @Published public private(set) var state: MicrophoneState = .idle
    @Published public private(set) var inputs: [Microphone] = []
    @Published public private(set) var selectedID = ""
    @Published public private(set) var verifiedInput: Microphone?
    @Published public private(set) var peakDB: Float = -120
    @Published public private(set) var inputGain: Float?
    @Published public private(set) var events: [String] = []
    private let hardware: MicrophoneHardware
    private var generation = 0
    private var active = false
    private var elapsedTicks = 0

    public var isCapturing: Bool { state == .testing || state == .cameraHandoff }
    public var selected: Microphone? { inputs.first { $0.id == selectedID } }
    public var canTest: Bool { state == .ready && verifiedInput?.id == selectedID }
    public var canHandoff: Bool { (state == .ready || state == .testing) && verifiedInput?.id == selectedID }

    public init(hardware: MicrophoneHardware) {
        self.hardware = hardware
        hardware.onEvent = { [weak self] event in self?.receive(event) }
    }

    public func discover() async {
        await prepare(id: selectedID)
    }

    public func select(_ id: String) async {
        guard !id.isEmpty else { return }
        await prepare(id: id)
    }

    private func prepare(id: String) async {
        generation += 1
        let request = generation
        hardware.stopLevelTest()
        state = .preparing; peakDB = -120; verifiedInput = nil
        if !id.isEmpty { selectedID = id }
        let permitted = await hardware.requestPermission()
        guard generation == request else { return }
        guard permitted else {
            fail("Allow microphone access in iPhone Settings → Privacy & Security → Microphone → ClearMic.")
            return
        }
        do {
            try hardware.activate()
            active = true
            inputs = hardware.inputs
            guard !selectedID.isEmpty else {
                state = .idle
                log("Available inputs refreshed. Choose a microphone.")
                return
            }
            guard inputs.contains(where: { $0.id == selectedID }) else { loseSource(); return }
            try hardware.select(selectedID)
            // Route selection is a preference; verify the actual port after it settles.
            for _ in 0..<15 {
                guard request == generation else { return }
                if hardware.activeInput?.id == selectedID {
                    verifiedInput = hardware.activeInput
                    inputGain = hardware.gain
                    state = .ready
                    log("Verified in ClearMic: \(verifiedInput?.name ?? "microphone").")
                    return
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard request == generation else { return }
            fail("iOS did not switch to the selected microphone. Reconnect it in Settings → Bluetooth, then try again.")
        } catch {
            guard request == generation else { return }
            fail(error.localizedDescription)
        }
    }

    public func startTest() {
        guard canTest else { return }
        guard hardware.activeInput?.id == selectedID else { loseSource(); return }
        do {
            try hardware.startLevelTest(duration: 30)
            guard hardware.activeInput?.id == selectedID else { loseSource(); return }
            elapsedTicks = 0
            state = .testing
            log("Level test started. Temporary audio is deleted when the test ends.")
        } catch { fail(error.localizedDescription) }
    }

    public func stopTest() {
        guard state == .testing else { return }
        hardware.stopLevelTest(); peakDB = -120
        if hardware.activeInput?.id == selectedID { state = .ready }
        else { loseSource() }
    }

    public func prepareCamera() {
        guard canHandoff else { return }
        guard hardware.activeInput?.id == selectedID else { loseSource(); return }
        do {
            // Start a fresh bounded recording while still foregrounded, so iOS
            // can keep the selected input active as the user switches apps.
            try hardware.startLevelTest(duration: 300)
            guard hardware.activeInput?.id == selectedID else { loseSource(); return }
            peakDB = -120
            state = .cameraHandoff
            log("Microphone capture remains active for up to 5 minutes while switching apps. Another app may interrupt it; Camera input is not observable by ClearMic.")
        } catch { fail(error.localizedDescription) }
    }

    private func finishHandoff(_ reason: String) {
        hardware.stopLevelTest(); peakDB = -120
        state = .cameraReleased
        log(reason)
    }

    public func setGain(_ value: Float) {
        guard active, state == .ready || state == .testing, hardware.gain != nil else { return }
        do { try hardware.setGain(min(1, max(0, value))); inputGain = hardware.gain }
        catch { log("Input gain: \(error.localizedDescription)") }
    }

    public func stop() {
        generation += 1
        hardware.stopLevelTest()
        if active { try? hardware.deactivate() }
        active = false
        peakDB = -120; inputGain = nil; verifiedInput = nil; state = .idle
        log("ClearMic audio session stopped.")
    }

    public func poll() {
        guard isCapturing else { return }
        guard hardware.activeInput?.id == selectedID else { loseSource(); return }
        let level = hardware.peak()
        peakDB = level.isFinite ? min(0, max(-120, level)) : -120
        if state == .testing {
            elapsedTicks += 1
            if elapsedTicks >= 300 { stopTest() }
        }
    }

    public func returnedToForeground() {
        inputs = hardware.inputs
        // Opening Camera can take ownership. Do not reclaim the route automatically.
        if state == .cameraHandoff {
            if hardware.activeInput?.id != selectedID { loseSource() }
            else if !hardware.isRecording { finishHandoff("Background capture ended. Reconnect to try again.") }
            log("Returned from Camera. Its recorded input must be checked in the video.")
        } else if active, state == .ready || state == .testing {
            if hardware.activeInput?.id != selectedID { loseSource() }
        }
    }

    public var diagnostics: String {
        (["ClearMic iOS route prototype", "State: \(state.title)",
          "Selected input: \(selected?.name ?? "none")",
          "Last verified in ClearMic: \(verifiedInput?.name ?? "none")",
          "Camera audio input: not observable by this app"] + events).joined(separator: "\n")
    }

    private func receive(_ event: AudioEvent) {
        guard active else { return }
        switch event {
        case .routeChanged:
            inputs = hardware.inputs
            guard state != .preparing, state != .cameraReleased else { return }
            if state == .cameraHandoff {
                if hardware.activeInput?.id != selectedID { loseSource() }
                else { log("System route changed; selected input remains active.") }
            } else if hardware.activeInput?.id != selectedID && !selectedID.isEmpty { loseSource() }
        case .interrupted:
            hardware.stopLevelTest(); peakDB = -120
            if state == .cameraHandoff { finishHandoff("iOS interrupted ClearMic capture during handoff. Camera input must be checked in the video.") }
            else { generation += 1; state = .interrupted; verifiedInput = nil; log("Audio interrupted. Reconnect explicitly to resume.") }
        case .mediaReset:
            generation += 1; hardware.stopLevelTest(); active = false
            state = .interrupted; verifiedInput = nil; peakDB = -120
            log("iOS reset its audio service. Reconnect to prepare the microphone again.")
        case .testFinished:
            if state == .cameraHandoff { finishHandoff("The 5-minute background capture ended. Reconnect to try again.") }
            else { stopTest() }
        case .testFailed(let reason): fail(reason)
        }
    }

    private func loseSource() {
        generation += 1
        hardware.stopLevelTest(); peakDB = -120; verifiedInput = nil; inputGain = nil
        state = .sourceLost
        log("Selected microphone is unavailable. No substitute input will be tested automatically.")
    }

    private func fail(_ reason: String) {
        hardware.stopLevelTest(); peakDB = -120; verifiedInput = nil; inputGain = nil
        state = .failed(reason)
        log(reason)
    }

    private func log(_ text: String) {
        events.append("\(Date().formatted(date: .omitted, time: .standard)) \(text)")
        if events.count > 40 { events.removeFirst(events.count - 40) }
    }
}
