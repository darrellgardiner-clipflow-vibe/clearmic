import XCTest
@testable import RouteCore

@MainActor private final class Hardware: MicrophoneHardware {
    let bluetooth = Microphone(id: "dji", name: "DJI microphone", bluetooth: true)
    let phone = Microphone(id: "phone", name: "iPhone microphone", bluetooth: false)
    var inputs: [Microphone] = []
    var activeInput: Microphone?
    var gain: Float? = 0.5
    var onEvent: ((AudioEvent) -> Void)?
    var permission: () async -> Bool = { true }
    var activationCount = 0
    var deactivationCount = 0
    var chosen: [String] = []
    var recording = false
    var starts = 0
    var meter: Float = -18
    var testError: Error?

    init() { inputs = [phone, bluetooth]; activeInput = phone }
    func requestPermission() async -> Bool { await permission() }
    func activate() throws { activationCount += 1 }
    func select(_ id: String) throws { chosen.append(id); activeInput = inputs.first { $0.id == id } }
    func setGain(_ value: Float) throws { gain = value }
    func startLevelTest() throws {
        if let testError { throw testError }
        recording = true; starts += 1
    }
    func peak() -> Float { meter }
    func stopLevelTest() { recording = false }
    func deactivate() throws { deactivationCount += 1 }
}

final class MicrophoneSessionTests: XCTestCase {
    @MainActor func testDiscoveryDoesNotChooseOrRecordAnInput() async {
        let hardware = Hardware()
        let session = MicrophoneSession(hardware: hardware)
        await session.discover()
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.inputs.map(\.id), ["phone", "dji"])
        XCTAssertEqual(hardware.chosen, [])
        XCTAssertFalse(hardware.recording)
        XCTAssertNil(session.verifiedInput)
        XCTAssertFalse(session.canTest)
    }

    @MainActor func testBluetoothSelectionLevelTestAndCameraHandoffAreSeparateStates() async {
        let hardware = Hardware(), session: MicrophoneSession
        session = MicrophoneSession(hardware: hardware)
        await session.select("dji")
        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(session.verifiedInput?.name, "DJI microphone")
        XCTAssertTrue(session.canTest)
        session.startTest(); session.poll()
        XCTAssertEqual(session.state, .testing)
        XCTAssertEqual(session.peakDB, -18)
        XCTAssertTrue(hardware.recording)
        session.prepareCamera()
        XCTAssertEqual(session.state, .cameraHandoff)
        XCTAssertFalse(hardware.recording)
        XCTAssertEqual(hardware.deactivationCount, 0)
        hardware.onEvent?(.interrupted)
        XCTAssertEqual(session.state, .cameraHandoff)
        hardware.activeInput = hardware.phone
        hardware.onEvent?(.routeChanged)
        session.returnedToForeground()
        XCTAssertEqual(session.state, .cameraHandoff)
        XCTAssertEqual(hardware.activationCount, 1)
        XCTAssertEqual(hardware.chosen, ["dji"])
        XCTAssertTrue(session.diagnostics.contains("Camera audio input: not observable by this app"))
        session.stop()
        XCTAssertEqual(hardware.deactivationCount, 1)
        XCTAssertEqual(session.state, .idle)
    }

    @MainActor func testLostMicStopsCaptureAndRequiresExplicitReconnect() async {
        let hardware = Hardware(), session: MicrophoneSession
        session = MicrophoneSession(hardware: hardware)
        await session.select("dji")
        session.startTest()
        hardware.inputs = [hardware.phone]; hardware.activeInput = hardware.phone
        hardware.onEvent?(.routeChanged)
        XCTAssertEqual(session.state, .sourceLost)
        XCTAssertFalse(hardware.recording)
        XCTAssertFalse(session.canTest)
        XCTAssertNil(session.verifiedInput)
        hardware.inputs.append(hardware.bluetooth)
        hardware.onEvent?(.routeChanged)
        XCTAssertEqual(session.state, .sourceLost)
        XCTAssertEqual(hardware.chosen, ["dji"])
        await session.discover()
        XCTAssertEqual(session.state, .ready)
        XCTAssertEqual(session.selectedID, "dji")
        XCTAssertFalse(hardware.recording)
        XCTAssertEqual(hardware.chosen, ["dji", "dji"])
    }

    @MainActor func testRouteChangingBetweenReadyAndTestCannotRecordSubstitute() async {
        let hardware = Hardware(), session: MicrophoneSession
        session = MicrophoneSession(hardware: hardware)
        await session.select("dji")
        hardware.activeInput = hardware.phone
        session.startTest()
        XCTAssertEqual(session.state, .sourceLost)
        XCTAssertEqual(hardware.starts, 0)
        XCTAssertFalse(hardware.recording)
    }

    @MainActor func testPermissionDenialAndStopCancelPendingPermission() async {
        let hardware = Hardware(), session: MicrophoneSession
        session = MicrophoneSession(hardware: hardware)
        hardware.permission = { false }
        await session.select("dji")
        guard case .failed(let message) = session.state else { return XCTFail("Permission denied must explain recovery") }
        XCTAssertTrue(message.contains("Settings"))
        XCTAssertEqual(hardware.activationCount, 0)
        var resume: CheckedContinuation<Bool, Never>?
        hardware.permission = { await withCheckedContinuation { resume = $0 } }
        let selection = Task { await session.select("dji") }
        while resume == nil { await Task.yield() }
        session.stop()
        resume!.resume(returning: true)
        await selection.value
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(hardware.activationCount, 0)
        XCTAssertEqual(hardware.starts, 0)
    }

    @MainActor func testAnOldPermissionResponseCannotReplaceTheNewSelection() async {
        let hardware = Hardware(), session: MicrophoneSession
        session = MicrophoneSession(hardware: hardware)
        var resume: CheckedContinuation<Bool, Never>?
        hardware.permission = { await withCheckedContinuation { resume = $0 } }
        let old = Task { await session.select("phone") }
        while resume == nil { await Task.yield() }
        hardware.permission = { true }
        await session.select("dji")
        resume!.resume(returning: true)
        await old.value
        XCTAssertEqual(session.selectedID, "dji")
        XCTAssertEqual(session.verifiedInput?.id, "dji")
        XCTAssertEqual(hardware.chosen, ["dji"])
    }

    @MainActor func testThirtySecondLimitAndInvalidMeters() async {
        let hardware = Hardware(), session: MicrophoneSession
        session = MicrophoneSession(hardware: hardware)
        await session.select("dji")
        session.startTest()
        hardware.meter = .nan; session.poll()
        XCTAssertEqual(session.peakDB, -120)
        for _ in 0..<299 { session.poll() }
        XCTAssertEqual(session.state, .ready)
        XCTAssertFalse(hardware.recording)
        XCTAssertEqual(session.peakDB, -120)
    }

    @MainActor func testRecordingFailureStopsTestAndShowsReason() async {
        let hardware = Hardware(), session: MicrophoneSession
        session = MicrophoneSession(hardware: hardware)
        await session.select("dji")
        session.startTest()
        hardware.onEvent?(.testFailed("Input busy"))
        XCTAssertEqual(session.state, .failed("Input busy"))
        XCTAssertFalse(hardware.recording)
        XCTAssertNil(session.verifiedInput)
        XCTAssertFalse(session.canHandoff)
    }

    @MainActor func testInterruptionsNeverAutoResumeAndHardwareGainIsBounded() async {
        let hardware = Hardware(), session: MicrophoneSession
        session = MicrophoneSession(hardware: hardware)
        await session.select("dji")
        session.setGain(2)
        XCTAssertEqual(session.inputGain, 1)
        session.startTest()
        hardware.onEvent?(.interrupted)
        XCTAssertEqual(session.state, .interrupted)
        XCTAssertFalse(hardware.recording)
        session.returnedToForeground()
        XCTAssertEqual(hardware.activationCount, 1)
        XCTAssertEqual(session.state, .interrupted)
        await session.discover()
        hardware.onEvent?(.mediaReset)
        XCTAssertEqual(session.state, .interrupted)
        XCTAssertNil(session.verifiedInput)
        XCTAssertFalse(hardware.recording)
    }
}
