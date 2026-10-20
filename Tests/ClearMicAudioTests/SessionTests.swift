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
