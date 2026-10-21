import AVFoundation
import Foundation
import RouteCore

@MainActor final class IOSAudioHardware: NSObject, MicrophoneHardware, AVAudioRecorderDelegate {
    private let session = AVAudioSession.sharedInstance()
    private var recorder: AVAudioRecorder?
    private var observers: [NSObjectProtocol] = []
    private let testURL = FileManager.default.temporaryDirectory.appendingPathComponent("ClearMicLevelTest.caf")
    var onEvent: ((AudioEvent) -> Void)?

    override init() {
        super.init()
        try? FileManager.default.removeItem(at: testURL)
        for (notification, event) in [
            (AVAudioSession.routeChangeNotification, AudioEvent.routeChanged),
            (AVAudioSession.mediaServicesWereResetNotification, .mediaReset)
        ] {
            observers.append(NotificationCenter.default.addObserver(forName: notification, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onEvent?(event) }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw == AVAudioSession.InterruptionType.began.rawValue {
                Task { @MainActor in self?.onEvent?(.interrupted) }
            }
        })
    }

    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

    var inputs: [Microphone] { (session.availableInputs ?? []).map(Self.microphone) }
    var activeInput: Microphone? { session.currentRoute.inputs.first.map(Self.microphone) }
    var isRecording: Bool { recorder?.isRecording == true }
    var gain: Float? { session.isInputGainSettable ? session.inputGain : nil }

    func requestPermission() async -> Bool { await AVAudioApplication.requestRecordPermission() }

    func activate() throws {
        let options: AVAudioSession.CategoryOptions = [.mixWithOthers, .allowBluetoothHFP]
        try session.setCategory(.playAndRecord, mode: .default, options: options)
        try session.setActive(true)
    }

    func select(_ id: String) throws {
        guard let port = session.availableInputs?.first(where: { $0.uid == id }) else {
            throw AudioFailure("The selected microphone is no longer available.")
        }
        try session.setPreferredInput(port)
    }

    func setGain(_ value: Float) throws { try session.setInputGain(value) }

    func startLevelTest(duration: TimeInterval) throws {
        stopLevelTest()
        guard session.sampleRate > 0 else { throw AudioFailure("The input has no active sample rate. Reconnect it and try again.") }
        let recorder = try AVAudioRecorder(url: testURL, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: session.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ])
        self.recorder = recorder
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record(forDuration: duration) else {
            stopLevelTest()
            throw AudioFailure("iOS could not start the microphone test. Another app may be using the input.")
        }
    }

    func peak() -> Float {
        guard let recorder, recorder.isRecording else { return -120 }
        recorder.updateMeters()
        return recorder.peakPower(forChannel: 0)
    }

    func stopLevelTest() {
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        try? FileManager.default.removeItem(at: testURL)
    }

    func deactivate() throws {
        stopLevelTest()
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.onEvent?(flag ? .testFinished : .testFailed("The microphone test ended unexpectedly. Reconnect and try again."))
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let reason = error?.localizedDescription ?? "The microphone test could not record audio."
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            self.onEvent?(.testFailed(reason))
        }
    }

    private static func microphone(_ port: AVAudioSessionPortDescription) -> Microphone {
        Microphone(id: port.uid, name: port.portName,
                   bluetooth: port.portType == .bluetoothHFP || port.portType == .bluetoothLE)
    }
}

private struct AudioFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
