import ClearMicAudio
import CoreAudio
import XCTest

final class ProcessorTests: XCTestCase {
    private func render(_ input: [Float], controls: CMControls) -> [Float] {
        let processor = CMProcessorCreate(48000)!
        defer { CMProcessorDestroy(processor) }
        CMProcessorSetControls(processor, controls)
        var result = input
        result.withUnsafeMutableBufferPointer { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = min(256, buffer.count - offset)
                CMProcessorProcessMono(processor, buffer.baseAddress! + offset, UInt32(count))
                offset += count
            }
        }
        return result
    }

    private func tone(_ hz: Double, amplitude: Double = 0.1) -> [Float] {
        (0..<48000).map { Float(amplitude * sin(2 * .pi * hz * Double($0) / 48000)) }
    }

    private func rms(_ samples: [Float]) -> Double {
        let tail = samples.suffix(24000)
        return sqrt(tail.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(tail.count))
    }

    func testBypassIsDryAndMuteOverridesIt() {
        let input: [Float] = [-0.7, 0.2, 0, 0.8, -0.1]
        var controls = CMDefaultControls()
        controls.inputGainDB = 18; controls.makeupDB = 12; controls.bypass = 1
        XCTAssertEqual(render(input, controls: controls), input)
        controls.muted = 1
        XCTAssertEqual(render(input, controls: controls), [0, 0, 0, 0, 0])
    }

    func testHighPassAttenuatesRumbleAndPreservesSpeechBand() {
        var controls = CMDefaultControls()
        controls.mudGainDB = 0; controls.presenceGainDB = 0; controls.compressionEnabled = 0
        let low = tone(20), speech = tone(1000)
        XCTAssertLessThan(20 * log10(rms(render(low, controls: controls)) / rms(low)), -23)
        XCTAssertEqual(20 * log10(rms(render(speech, controls: controls)) / rms(speech)), 0, accuracy: 0.1)
    }

    func testEQCutsMudAndBoostsClarityAtSpecifiedFrequencies() {
        var controls = CMDefaultControls()
        controls.highPassHz = 0; controls.mudGainDB = -6; controls.presenceGainDB = 0; controls.compressionEnabled = 0
        let mud = tone(280)
        XCTAssertEqual(20 * log10(rms(render(mud, controls: controls)) / rms(mud)), -6, accuracy: 0.1)
        controls.mudGainDB = 0; controls.presenceGainDB = 3
        let presence = tone(3500)
        XCTAssertEqual(20 * log10(rms(render(presence, controls: controls)) / rms(presence)), 3, accuracy: 0.1)
    }

    func testBassShelfBoostsAndCutsLowsWithoutChangingHighs() {
        var controls = CMDefaultControls()
        controls.highPassHz = 0; controls.mudGainDB = 0; controls.presenceGainDB = 0
        controls.compressionEnabled = 0
        for gain: Float in [-6, 6] {
            controls.bassGainDB = gain
            let low = tone(20), corner = tone(120), high = tone(2000)
            XCTAssertEqual(20 * log10(rms(render(low, controls: controls)) / rms(low)), Double(gain), accuracy: 0.1)
            XCTAssertEqual(20 * log10(rms(render(corner, controls: controls)) / rms(corner)), Double(gain) / 2, accuracy: 0.1)
            XCTAssertEqual(20 * log10(rms(render(high, controls: controls)) / rms(high)), 0, accuracy: 0.1)
        }
    }

    func testAirShelfBoostsAndCutsHighsWithoutChangingLows() {
        var controls = CMDefaultControls()
        controls.highPassHz = 0; controls.mudGainDB = 0; controls.presenceGainDB = 0
        controls.compressionEnabled = 0
        for gain: Float in [-6, 6] {
            controls.airGainDB = gain
            let low = tone(200), corner = tone(8000), high = tone(20000)
            XCTAssertEqual(20 * log10(rms(render(low, controls: controls)) / rms(low)), 0, accuracy: 0.1)
            XCTAssertEqual(20 * log10(rms(render(corner, controls: controls)) / rms(corner)), Double(gain) / 2, accuracy: 0.1)
            XCTAssertEqual(20 * log10(rms(render(high, controls: controls)) / rms(high)), Double(gain), accuracy: 0.1)
        }
    }

    func testDeEsserReducesSibilantBandAndPreservesLowVoice() {
        var controls = CMDefaultControls()
        controls.highPassHz = 0; controls.mudGainDB = 0; controls.presenceGainDB = 0
        controls.compressionEnabled = 0; controls.deEssAmount = 1
        let low = tone(200), high = tone(7000)
        XCTAssertEqual(20 * log10(rms(render(low, controls: controls)) / rms(low)), 0, accuracy: 0.2)
        XCTAssertLessThan(20 * log10(rms(render(high, controls: controls)) / rms(high)), -2)
    }

    func testRoomAddsADecayingTailAndBypassStaysDry() {
        var controls = CMDefaultControls()
        controls.highPassHz = 0; controls.mudGainDB = 0; controls.presenceGainDB = 0
        controls.compressionEnabled = 0; controls.reverbMix = 0.2
        var impulse = [Float](repeating: 0, count: 96000)
        impulse[4800] = 0.5
        let output = render(impulse, controls: controls)
        XCTAssertTrue(output.allSatisfy(\.isFinite))
        let early = output[5000..<24000].reduce(0.0) { $0 + Double($1 * $1) }
        let late = output[72000..<96000].reduce(0.0) { $0 + Double($1 * $1) }
        XCTAssertGreaterThan(early, 0.0001)
        XCTAssertLessThan(late, early * 0.01)
        controls.bypass = 1
        XCTAssertEqual(render(impulse, controls: controls), impulse)
        controls.muted = 1
        XCTAssertEqual(render(impulse, controls: controls), [Float](repeating: 0, count: impulse.count))
    }

    func testMuteClearsRoomSoMutedSpeechCannotReturnInTheTail() {
        let processor = CMProcessorCreate(48000)!
        defer { CMProcessorDestroy(processor) }
        var controls = CMDefaultControls()
        controls.highPassHz = 0; controls.mudGainDB = 0; controls.presenceGainDB = 0
        controls.compressionEnabled = 0; controls.reverbMix = 0.25
        CMProcessorSetControls(processor, controls)
        var speech = [Float](repeating: 0, count: 10000)
        speech[4800] = 0.5
        speech.withUnsafeMutableBufferPointer { CMProcessorProcessMono(processor, $0.baseAddress!, UInt32($0.count)) }
        controls.muted = 1
        CMProcessorSetControls(processor, controls)
        var muted = [Float](repeating: 0.1, count: 480)
        muted.withUnsafeMutableBufferPointer { CMProcessorProcessMono(processor, $0.baseAddress!, UInt32($0.count)) }
        controls.muted = 0
        CMProcessorSetControls(processor, controls)
        var after = [Float](repeating: 0, count: 10000)
        after.withUnsafeMutableBufferPointer { CMProcessorProcessMono(processor, $0.baseAddress!, UInt32($0.count)) }
        XCTAssertTrue(after.allSatisfy { abs($0) < 0.000001 }, "Muted speech must not reappear as reverb")
    }

    func testCompressorSettlesOnExpectedStaticCurve() {
        var controls = CMDefaultControls()
        controls.highPassHz = 0; controls.mudGainDB = 0; controls.presenceGainDB = 0
        controls.thresholdDB = -18; controls.ratio = 3
        let output = render([Float](repeating: pow(10, -6.0 / 20), count: 96000), controls: controls)
        XCTAssertEqual(20 * log10(Double(output.last!)), -14, accuracy: 0.1)
    }

    func testLimiterContainsBoostedTransientsAndRejectsInvalidSamples() {
        var controls = CMDefaultControls()
        controls.inputGainDB = 24; controls.makeupDB = 18
        let input = [Float](repeating: 1, count: 2000) + [.nan, .infinity, -.infinity, 0, -1]
        let output = render(input, controls: controls)
        XCTAssertTrue(output.allSatisfy { $0.isFinite && abs($0) <= pow(10, -1.0 / 20) + 0.000001 })
    }

    func testInvalidControlsCannotPoisonProcessor() {
        var controls = CMDefaultControls()
        controls.inputGainDB = .nan; controls.highPassHz = .infinity; controls.ratio = 0
        controls.thresholdDB = -.infinity
        XCTAssertTrue(render(tone(1000), controls: controls).allSatisfy(\.isFinite))
        XCTAssertNil(CMProcessorCreate(.nan))
    }

    func testRoutingSelectsOneChannelAndLeavesPhysicalOutputsSilent() {
        let (destination, errors) = routeFixture()
        XCTAssertEqual(destination, [0, 0, 0.1, 0.1, 0, 0, -0.2, -0.2, 0, 0, 0.3, 0.3])
        XCTAssertEqual(errors, 0)
    }

    func testHeadphoneMonitorGetsProcessedAudioAtIndependentLevel() {
        let (destination, errors) = routeFixture(monitorOffset: 0, monitorChannels: 2)
        let expected: [Float] = [0.05, 0.05, 0.1, 0.1, -0.1, -0.1, -0.2, -0.2, 0.15, 0.15, 0.3, 0.3]
        for (actual, expected) in zip(destination, expected) { XCTAssertEqual(actual, expected, accuracy: 0.000001) }
        XCTAssertEqual(errors, 0)
    }

    func testMuteTransitionsRampWithoutAnAbruptStep() {
        let processor = CMProcessorCreate(48000)!
        defer { CMProcessorDestroy(processor) }
        var controls = CMDefaultControls()
        controls.bypass = 1
        CMProcessorSetControls(processor, controls)
        var samples = [Float](repeating: 0.25, count: 480)
        samples.withUnsafeMutableBufferPointer { CMProcessorProcessMono(processor, $0.baseAddress!, 480) }
        controls.muted = 1
        CMProcessorSetControls(processor, controls)
        samples = [Float](repeating: 0.25, count: 480)
        samples.withUnsafeMutableBufferPointer { CMProcessorProcessMono(processor, $0.baseAddress!, 480) }
        XCTAssertGreaterThan(samples[0], 0.24)
        XCTAssertEqual(samples[239], 0)
        XCTAssertTrue(samples.suffix(240).allSatisfy { $0 == 0 })
        for pair in zip([Float(0.25)] + samples, samples) { XCTAssertLessThanOrEqual(abs(pair.0 - pair.1), 0.00105) }
        controls.muted = 0
        CMProcessorSetControls(processor, controls)
        samples = [Float](repeating: 0.25, count: 480)
        samples.withUnsafeMutableBufferPointer { CMProcessorProcessMono(processor, $0.baseAddress!, 480) }
        XCTAssertEqual(samples.last!, 0.25)
        XCTAssertLessThan(samples[0], 0.002)
    }

    func testSeparateChannelBuffersRouteWithoutLeakingOtherInputs() {
        let processor = CMProcessorCreate(48000)!
        defer { CMProcessorDestroy(processor) }
        var controls = CMDefaultControls(); controls.bypass = 1
        CMProcessorSetControls(processor, controls)
        CMProcessorSetRouting(processor, 1, 2, .max, 0)
        let buffers = (0..<6).map { index -> UnsafeMutablePointer<Float> in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: 3)
            pointer.initialize(repeating: index == 0 ? 0.9 : index == 1 ? 0.2 : 99, count: 3)
            return pointer
        }
        let inputMemory = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size, alignment: 8)
        let outputMemory = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<AudioBufferList>.size + 3 * MemoryLayout<AudioBuffer>.size, alignment: 8)
        defer {
            for pointer in buffers { pointer.deinitialize(count: 3); pointer.deallocate() }
            inputMemory.deallocate(); outputMemory.deallocate()
        }
        let input = inputMemory.bindMemory(to: AudioBufferList.self, capacity: 1)
        let output = outputMemory.bindMemory(to: AudioBufferList.self, capacity: 1)
        input.initialize(to: AudioBufferList(mNumberBuffers: 2, mBuffers: AudioBuffer()))
        output.initialize(to: AudioBufferList(mNumberBuffers: 4, mBuffers: AudioBuffer()))
        let inputList = UnsafeMutableAudioBufferListPointer(input), outputList = UnsafeMutableAudioBufferListPointer(output)
        for index in 0..<2 { inputList[index] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 12, mData: buffers[index]) }
        for index in 0..<4 { outputList[index] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 12, mData: buffers[index + 2]) }
        var stamp = AudioTimeStamp()
        withUnsafePointer(to: &stamp) { time in
            XCTAssertEqual(CMRender(0, time, input, time, output, time, UnsafeMutableRawPointer(processor)), 0)
        }
        XCTAssertEqual(Array(UnsafeBufferPointer(start: buffers[2], count: 3)), [0, 0, 0])
        XCTAssertEqual(Array(UnsafeBufferPointer(start: buffers[3], count: 3)), [0, 0, 0])
        XCTAssertEqual(Array(UnsafeBufferPointer(start: buffers[4], count: 3)), [0.2, 0.2, 0.2])
        XCTAssertEqual(Array(UnsafeBufferPointer(start: buffers[5], count: 3)), [0.2, 0.2, 0.2])
    }

    private func routeFixture(monitorOffset: UInt32 = .max, monitorChannels: UInt32 = 0) -> ([Float], UInt64) {
        let processor = CMProcessorCreate(48000)!
        defer { CMProcessorDestroy(processor) }
        var controls = CMDefaultControls(); controls.bypass = 1; controls.monitorGainDB = -6.0206
        CMProcessorSetControls(processor, controls)
        CMProcessorSetRouting(processor, 1, 2, monitorOffset, monitorChannels)
        var source: [Float] = [0.9, 0.1, 0.8, -0.2, 0.7, 0.3]
        var destination = [Float](repeating: 99, count: 12)
        source.withUnsafeMutableBytes { sourceBytes in
            destination.withUnsafeMutableBytes { destinationBytes in
                var input = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: 2, mDataByteSize: UInt32(sourceBytes.count), mData: sourceBytes.baseAddress))
                var output = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: 4, mDataByteSize: UInt32(destinationBytes.count), mData: destinationBytes.baseAddress))
                var stamp = AudioTimeStamp()
                withUnsafePointer(to: &stamp) { time in
                    XCTAssertEqual(CMRender(0, time, &input, time, &output, time, UnsafeMutableRawPointer(processor)), 0)
                }
            }
        }
        return (destination, CMProcessorGetMeters(processor).routingErrors)
    }
}
