import CoreAudio
import Foundation

// Uses the application's actual aggregate configuration; never starts audio I/O.
@main
enum RouteProbe {
    static func main() throws {
        let devices = AudioHardware.devices()
        let arguments = CommandLine.arguments.dropFirst().compactMap(UInt32.init)
        if arguments.isEmpty {
            for device in devices {
                print("\(device.id): \(device.name), \(device.inputChannels) in / \(device.outputChannels) out, \(device.sampleRate) Hz")
            }
            print("Pass source device ID followed by zero or more output IDs to check a route without capturing audio.")
            return
        }
        guard let source = devices.first(where: { $0.id == arguments[0] }), source.inputChannels > 0 else {
            throw RouteError("Choose an available input device ID.")
        }
        let outputs = try arguments.dropFirst().map { id -> AudioDevice in
            guard let device = devices.first(where: { $0.id == id }), device.outputChannels > 0 else {
                throw RouteError("Choose an available output device ID.")
            }
            return device
        }
        guard outputs.count <= 2 else { throw RouteError("At most two output devices are supported by this probe.") }
        let description = AudioHardware.aggregateDescription(sourceUID: source.uid,
                sendUID: outputs.count == 2 ? outputs[0].uid : nil, monitorUID: outputs.last?.uid)
        var aggregate: AudioObjectID = 0
        try AudioHardware.check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate), "Create probe route")
        defer { AudioHardwareDestroyAggregateDevice(aggregate) }
        let inputCount = AudioHardware.channels(aggregate, scope: kAudioDevicePropertyScopeInput)
        let outputCount = AudioHardware.channels(aggregate, scope: kAudioDevicePropertyScopeOutput)
        let separate = outputs.filter { $0.uid != source.uid }
        let expectedInput = source.inputChannels + separate.reduce(0) { $0 + $1.inputChannels }
        let expectedOutput = source.outputChannels + separate.reduce(0) { $0 + $1.outputChannels }
        guard inputCount == expectedInput, outputCount == expectedOutput else {
            throw RouteError("Route lost channels: \(inputCount)/\(outputCount), expected \(expectedInput)/\(expectedOutput).")
        }
        try AudioHardware.validateFloatStreams(aggregate, scope: kAudioDevicePropertyScopeInput)
        if outputCount > 0 { try AudioHardware.validateFloatStreams(aggregate, scope: kAudioDevicePropertyScopeOutput) }
        print("PASS: input channels \(inputCount), independently addressed output channels \(outputCount), 48 kHz Float32.")
    }
}
