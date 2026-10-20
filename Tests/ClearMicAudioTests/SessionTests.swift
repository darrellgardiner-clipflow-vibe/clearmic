import ClearMicAudio
import CoreAudio
import XCTest
@testable import ClearMic

private final class TestRoute: AudioRouting {
    let sourceID: AudioObjectID
    let monitorID: AudioObjectID? = nil
    var stopped = false
    init(_ source: AudioDevice) { sourceID = source.id }
    func update(_ controls: CMControls) {}
    func meters() -> CMMeters { CMMeters() }
    func stop() { stopped = true }
}

final class SessionTests: XCTestCase {
    func testNewEQBandsPreserveExistingSettingsAndRoundTrip() throws {
        let old = Data(#"{"inputGain":11,"makeup":8,"noiseReduction":true}"#.utf8)
        var settings = VoiceSettings.load(old)
        XCTAssertEqual(settings.inputGain, 11)
        XCTAssertEqual(settings.makeup, 8)
        XCTAssertTrue(settings.noiseReduction)
        XCTAssertEqual(settings.bass, 0)
        XCTAssertEqual(settings.air, 0)
        settings.bass = 3; settings.air = -2
        let restored = VoiceSettings.load(try JSONEncoder().encode(settings))
        XCTAssertEqual(restored.bass, 3)
        XCTAssertEqual(restored.air, -2)
    }

    @MainActor func testSavedPresetPersistsAndPreservesRoutingAndMute() {
        let suite = "ClearMicTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        func makeSession() -> Session {
            Session(defaults: defaults, listDevices: { [] }, permission: { false }, pollDevices: false)
        }
        let session = makeSession()
        session.settings.inputGain = 11; session.settings.makeup = 8
        session.settings.bass = 3; session.settings.deEss = 35; session.settings.reverb = 5
        session.savePreset(name: "  Podcast  ")
        XCTAssertEqual(session.presets.count, 1)
        XCTAssertEqual(session.presets[0].name, "Podcast")
        let id = session.presets[0].id
        session.settings.bass = 4
        session.savePreset(name: "podcast")
        XCTAssertEqual(session.presets.count, 1, "Saving the same name should update it")
        XCTAssertEqual(session.presets[0].id, id)
        session.savePreset(name: "   ")
        XCTAssertEqual(session.presets.count, 1)
        let restored = makeSession()
        XCTAssertEqual(restored.presets.count, 1)
        restored.settings.sourceUID = "another-mic"; restored.settings.channel = 1
        restored.settings.monitorUID = "headphones"; restored.settings.monitorGain = -6
        restored.settings.muted = true; restored.settings.bypass = true
        restored.settings.inputGain = 0; restored.settings.bass = 0
        restored.applyPreset(id)
        XCTAssertEqual(restored.settings.inputGain, 11)
        XCTAssertEqual(restored.settings.makeup, 8)
        XCTAssertEqual(restored.settings.bass, 4)
        XCTAssertEqual(restored.settings.deEss, 35)
        XCTAssertEqual(restored.settings.reverb, 5)
        XCTAssertEqual(restored.settings.sourceUID, "another-mic")
        XCTAssertEqual(restored.settings.channel, 1)
        XCTAssertEqual(restored.settings.monitorUID, "headphones")
        XCTAssertEqual(restored.settings.monitorGain, -6)
        XCTAssertTrue(restored.settings.muted)
        XCTAssertTrue(restored.settings.bypass)
        XCTAssertFalse(restored.running)
    }

    @MainActor func testLostSourceReconnectsBySavedUIDWithoutSelectorChanges() async {
        let suite = "ClearMicTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = AudioDevice(id: 1, uid: "usb", name: "USB microphone", inputChannels: 2, outputChannels: 0, sampleRate: 48000)
        let returned = AudioDevice(id: 2, uid: "usb", name: "USB microphone", inputChannels: 2, outputChannels: 0, sampleRate: 48000)
        var inventory = [original]
        var routes: [TestRoute] = []
        let session = Session(defaults: defaults, listDevices: { inventory }, permission: { true }, makeRoute: { source, _, _, _ in
            let route = TestRoute(source); routes.append(route); return route
        }, pollDevices: false)
        session.selectSource("usb")
        session.settings.channel = 1
        await session.start()
        XCTAssertTrue(session.running)
        inventory = []
        session.refreshDevices()
        XCTAssertFalse(session.running)
        XCTAssertTrue(session.sourceLost)
        XCTAssertTrue(routes[0].stopped)
        XCTAssertEqual(session.settings.sourceUID, "usb")
        await session.reconnectSource()
        XCTAssertFalse(session.running)
        XCTAssertTrue(session.sourceLost)
        XCTAssertEqual(routes.count, 1)
        inventory = [returned]
        session.refreshDevices()
        XCTAssertFalse(session.running, "Replugging must not automatically resume capture")
        await session.reconnectSource()
        XCTAssertTrue(session.running)
        XCTAssertFalse(session.sourceLost)
        XCTAssertEqual(routes.map(\.sourceID), [1, 2])
        XCTAssertEqual(session.settings.channel, 1)
        session.stop()
    }

    @MainActor func testStalledBuffersOfferReconnectEvenIfDeviceStillEnumerates() async {
        let suite = "ClearMicTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = AudioDevice(id: 1, uid: "usb", name: "USB microphone", inputChannels: 1, outputChannels: 0, sampleRate: 48000)
        let session = Session(defaults: defaults, listDevices: { [device] }, permission: { true }, makeRoute: { source, _, _, _ in TestRoute(source) }, pollDevices: false)
        session.selectSource("usb")
        await session.start()
        for _ in 0..<31 { session.pollAudio() }
        XCTAssertFalse(session.running)
        XCTAssertTrue(session.sourceLost)
        XCTAssertEqual(session.selectedDevice?.uid, "usb")
        await session.reconnectSource()
        XCTAssertTrue(session.running)
        XCTAssertFalse(session.sourceLost)
        session.stop()
    }

    @MainActor func testSwitchingActiveSourceResumesAndResetsChannel() async throws {
        let suite = "ClearMicTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let usb = AudioDevice(id: 1, uid: "usb", name: "USB", inputChannels: 2, outputChannels: 0, sampleRate: 48000)
        let mono = AudioDevice(id: 2, uid: "mono", name: "Mono", inputChannels: 1, outputChannels: 0, sampleRate: 48000)
        var routes: [TestRoute] = []
        var channels: [Int] = []
        let session = Session(defaults: defaults, listDevices: { [usb, mono] }, permission: { true }, makeRoute: { source, channel, _, _ in
            let route = TestRoute(source); routes.append(route); channels.append(channel); return route
        }, pollDevices: false)
        session.selectSource("usb")
        session.settings.channel = 1
        await session.start()
        XCTAssertTrue(session.running)
        session.selectSource("mono")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(session.running)
        XCTAssertEqual(routes.map(\.sourceID), [1, 2])
        XCTAssertEqual(channels, [1, 0])
        XCTAssertTrue(routes[0].stopped)
        session.stop()
        session.selectSource("usb")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(session.running)
        XCTAssertEqual(routes.count, 2, "Selecting while stopped must not start capture")
    }

    @MainActor func testStopCancelsQueuedSourceRestart() async {
        let suite = "ClearMicTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let devices = (1...2).map { AudioDevice(id: UInt32($0), uid: "mic\($0)", name: "Mic", inputChannels: 1, outputChannels: 0, sampleRate: 48000) }
        var starts = 0
        let session = Session(defaults: defaults, listDevices: { devices }, permission: { true }, makeRoute: { source, _, _, _ in
            starts += 1; return TestRoute(source)
        }, pollDevices: false)
        session.selectSource("mic1")
        await session.start()
        session.selectSource("mic2")
        session.stop()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(session.running)
        XCTAssertEqual(starts, 1)
    }
    @MainActor func testChangingSourceWhilePermissionIsPendingCannotStartOldRoute() async {
        let suite = "ClearMicTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let devices = (1...2).map { AudioDevice(id: UInt32($0), uid: "mic\($0)", name: "Mic", inputChannels: 1, outputChannels: 0, sampleRate: 48000) }
        var pending: CheckedContinuation<Bool, Never>?
        var requests = 0
        var sources: [AudioObjectID] = []
        let session = Session(defaults: defaults, listDevices: { devices }, permission: {
            requests += 1
            if requests == 1 { return await withCheckedContinuation { pending = $0 } }
            return true
        }, makeRoute: { source, _, _, _ in
            sources.append(source.id); return TestRoute(source)
        }, pollDevices: false)
        session.selectSource("mic1")
        let initial = Task { await session.start() }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(session.starting)
        session.selectSource("mic2")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(sources, [2])
        pending?.resume(returning: true)
        await initial.value
        XCTAssertEqual(sources, [2], "An old permission response must not create another route")
        XCTAssertTrue(session.running)
        session.stop()
    }

    @MainActor func testRapidSourceChangesKeepProcessingIntent() async {
        let suite = "ClearMicTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let devices = (1...3).map { AudioDevice(id: UInt32($0), uid: "mic\($0)", name: "Mic", inputChannels: 1, outputChannels: 0, sampleRate: 48000) }
        var sources: [AudioObjectID] = []
        let session = Session(defaults: defaults, listDevices: { devices }, permission: { true }, makeRoute: { source, _, _, _ in
            sources.append(source.id); return TestRoute(source)
        }, pollDevices: false)
        session.selectSource("mic1")
        await session.start()
        session.selectSource("mic2")
        session.selectSource("mic3")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(session.running)
        XCTAssertEqual(sources, [1, 3])
        session.stop()
    }

}
