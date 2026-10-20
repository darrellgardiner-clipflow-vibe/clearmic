import AVFoundation
import ClearMicAudio
import XCTest

final class NoiseReductionTests: XCTestCase {
    private func render(_ input: [Float], enabled: Bool, chunks: [Int] = [256], bypass: Bool = false, muted: Bool = false) -> [Float] {
        let processor = CMProcessorCreate(48000)!
        defer { CMProcessorDestroy(processor) }
        var controls = CMDefaultControls()
        controls.highPassHz = 0; controls.mudGainDB = 0; controls.presenceGainDB = 0
        controls.compressionEnabled = 0; controls.noiseReductionEnabled = enabled ? 1 : 0
        controls.bypass = bypass ? 1 : 0; controls.muted = muted ? 1 : 0
        CMProcessorSetControls(processor, controls)
        var output = input
        output.withUnsafeMutableBufferPointer { buffer in
            var position = 0, chunk = 0
            while position < buffer.count {
                let count = min(chunks[chunk % chunks.count], buffer.count - position)
                CMProcessorProcessMono(processor, buffer.baseAddress! + position, UInt32(count))
                position += count; chunk += 1
            }
        }
        return output
    }

    private func noise(_ count: Int) -> [Float] {
        var seed: UInt32 = 731
        return (0..<count).map { _ in
            seed = seed &* 1664525 &+ 1013904223
            return (Float(seed >> 8) / Float(0xFFFFFF) * 2 - 1) * 0.015
        }
    }

    private func energy(_ samples: ArraySlice<Float>) -> Double {
        samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(max(1, samples.count))
    }

    func testSteadyNoiseIsReducedAfterWarmup() {
        let input = noise(96000)
        let output = render(input, enabled: true)
        let reduction = 10 * log10(energy(output.suffix(48000)) / energy(input.suffix(48000)))
        XCTAssertLessThan(reduction, -8, "Noise reduction must do more than add a control")
        XCTAssertTrue(output.allSatisfy(\.isFinite))
    }

    func testSilenceAndInvalidSamplesStayFiniteWithCleanup() {
        var input = [Float](repeating: 0, count: 12000)
        input[100] = .nan; input[900] = .infinity
        XCTAssertEqual(render(input, enabled: true), [Float](repeating: 0, count: input.count))
    }

    func testFramingIsIndependentOfAudioCallbackSize() {
        let input = noise(12000)
        let regular = render(input, enabled: true, chunks: [480])
        let irregular = render(input, enabled: true, chunks: [1, 127, 256, 511, 1024])
        XCTAssertEqual(regular, irregular)
    }

    func testBypassAndMuteOverrideNoiseReduction() {
        let input = noise(12000)
        XCTAssertEqual(render(input, enabled: true, bypass: true), input)
        XCTAssertEqual(render(input, enabled: true, bypass: true, muted: true), [Float](repeating: 0, count: input.count))
    }

    func testSpeechSurvivesAlongsideNoise() throws {
        let url = Bundle.module.url(forResource: "speech", withExtension: "wav", subdirectory: "Fixtures")!
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let clean = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        let background = noise(clean.count)
        let mixed = zip(clean, background).map(+)
        let speechOutput = render(clean, enabled: true)
        let noisyOutput = render(mixed, enabled: true)
        XCTAssertGreaterThan(energy(noisyOutput[...]), energy(clean[...]) * 0.15, "Suppressing everything is not speech cleanup")
        let residual = zip(speechOutput, noisyOutput).map { $1 - $0 }
        XCTAssertLessThan(energy(residual.suffix(48000)), energy(background.suffix(48000)) * 0.5)
    }
}
