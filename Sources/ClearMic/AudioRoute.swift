import CoreAudio
import ClearMicAudio
import Foundation

struct AudioDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let inputChannels: Int
    let outputChannels: Int
    let sampleRate: Double
}

enum AudioHardware {
    static let microphoneUID = "ClearMic_UID"
    static let sendUID = "ClearMic_2_UID"

    static func aggregateDescription(sourceUID: String, sendUID: String?, monitorUID: String?) -> [String: Any] {
        var subdevices: [[String: Any]] = [[kAudioSubDeviceUIDKey: sourceUID, kAudioSubDeviceDriftCompensationKey: 0]]
        if let sendUID { subdevices.append([kAudioSubDeviceUIDKey: sendUID, kAudioSubDeviceDriftCompensationKey: 1]) }
        if let monitorUID, monitorUID != sourceUID {
            subdevices.append([kAudioSubDeviceUIDKey: monitorUID, kAudioSubDeviceDriftCompensationKey: 1])
        }
        return [
            kAudioAggregateDeviceUIDKey: "org.clearmic.route.\(UUID().uuidString)",
            kAudioAggregateDeviceNameKey: "ClearMic processing",
            kAudioAggregateDeviceIsPrivateKey: true,
            // On macOS 26, true creates a multi-output device with no input streams.
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceMainSubDeviceKey: sourceUID,
            kAudioAggregateDeviceSubDeviceListKey: subdevices
        ]
    }

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw RouteError("\(operation) failed (Core Audio \(status)).") }
    }

    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var property = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    static func rate(_ id: AudioObjectID) -> Double {
        var property = address(kAudioDevicePropertyNominalSampleRate), value = 0.0
        var size = UInt32(MemoryLayout<Double>.size)
        _ = AudioObjectGetPropertyData(id, &property, 0, nil, &size, &value)
        return value
    }

    static func channels(_ id: AudioObjectID, scope: AudioObjectPropertyScope) -> Int {
        var property = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &property, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(id, &property, 0, nil, &size, memory) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func devices() -> [AudioDevice] {
        var property = address(kAudioHardwarePropertyDevices), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let result = ids.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, $0.baseAddress!)
        }
        guard result == noErr else { return [] }
        return ids.compactMap { id in
            guard let uid = string(id, kAudioDevicePropertyDeviceUID), let name = string(id, kAudioObjectPropertyName) else { return nil }
            return AudioDevice(id: id, uid: uid, name: name,
                               inputChannels: channels(id, scope: kAudioDevicePropertyScopeInput),
                               outputChannels: channels(id, scope: kAudioDevicePropertyScopeOutput), sampleRate: rate(id))
        }
    }

    static func resolve(_ uid: String) -> AudioObjectID? {
        var property = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var value = AudioObjectID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioObjectID>.size)
        let keyString = uid as CFString
        var key = Unmanaged.passUnretained(keyString)
        let result = withExtendedLifetime(keyString) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property,
                                      UInt32(MemoryLayout<Unmanaged<CFString>>.size), &key, &size, &value)
        }
        return result == noErr && value != kAudioObjectUnknown ? value : nil
    }

    static func validateFloatStreams(_ id: AudioObjectID, scope: AudioObjectPropertyScope) throws {
        var property = address(kAudioDevicePropertyStreams, scope: scope), size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(id, &property, 0, nil, &size), "Read streams")
        guard size > 0 else { throw RouteError("The audio route has no streams.") }
        var streams = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        try streams.withUnsafeMutableBytes {
            try check(AudioObjectGetPropertyData(id, &property, 0, nil, &size, $0.baseAddress!), "Read stream IDs")
        }
        for stream in streams {
            var format = AudioStreamBasicDescription()
            var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var formatProperty = address(kAudioStreamPropertyVirtualFormat)
            try check(AudioObjectGetPropertyData(stream, &formatProperty, 0, nil, &formatSize, &format), "Read stream format")
            guard format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
                  format.mBitsPerChannel == 32,
                  format.mBytesPerFrame == 4 * (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? 1 : format.mChannelsPerFrame),
                  format.mSampleRate == 48000 else {
                throw RouteError("This device needs a 48 kHz, 32-bit float Core Audio stream. Check Audio MIDI Setup.")
            }
        }
    }
}

struct RouteError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

protocol AudioRouting: AnyObject {
    var sourceID: AudioObjectID { get }
    var monitorID: AudioObjectID? { get }
    func update(_ controls: CMControls)
    func meters() -> CMMeters
    func stop()
}

final class AudioRoute: AudioRouting {
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var processor: OpaquePointer?
    let sourceID: AudioObjectID
    let monitorID: AudioObjectID?
    private(set) var lastMeters = CMMeters()

    init(source: AudioDevice, channel: Int, monitor: AudioDevice?, controls: CMControls) throws {
        sourceID = source.id
        monitorID = monitor?.id
        guard source.uid != AudioHardware.microphoneUID, !source.uid.hasPrefix("org.clearmic.route.") else {
            throw RouteError("Choose a physical microphone to avoid a feedback loop.")
        }
        guard channel >= 0 && channel < source.inputChannels else { throw RouteError("That input channel is unavailable.") }
        guard abs(source.sampleRate - 48000) < 1 else {
            throw RouteError("\(source.name) provides \(Int(source.sampleRate)) Hz. ClearMic currently needs a 48,000 Hz input; Bluetooth microphones may not support it. Choose a 48 kHz microphone, or set a supported interface to 48,000 Hz in Audio MIDI Setup.")
        }
        let hasVirtual = AudioHardware.resolve(AudioHardware.microphoneUID) != nil && AudioHardware.resolve(AudioHardware.sendUID) != nil
        if let monitor {
            guard monitor.outputChannels > 0, monitor.uid != AudioHardware.microphoneUID,
                  monitor.uid != AudioHardware.sendUID else {
                throw RouteError("Choose an available headphone output. Bluetooth may add noticeable delay.")
            }
        }
        do {
            let separateMonitor = monitor != nil && monitor!.uid != source.uid
            let description = AudioHardware.aggregateDescription(sourceUID: source.uid,
                                                                 sendUID: hasVirtual ? AudioHardware.sendUID : nil,
                                                                 monitorUID: monitor?.uid)
            try AudioHardware.check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate), "Create audio route")
            try AudioHardware.validateFloatStreams(aggregate, scope: kAudioDevicePropertyScopeInput)
            if AudioHardware.channels(aggregate, scope: kAudioDevicePropertyScopeOutput) > 0 {
                try AudioHardware.validateFloatStreams(aggregate, scope: kAudioDevicePropertyScopeOutput)
            }
            let extraInputs = separateMonitor ? monitor!.inputChannels : 0
            let virtualChannels = hasVirtual ? 2 : 0
            let extraOutputs = separateMonitor ? monitor!.outputChannels : 0
            guard AudioHardware.channels(aggregate, scope: kAudioDevicePropertyScopeInput) == source.inputChannels + extraInputs,
                  AudioHardware.channels(aggregate, scope: kAudioDevicePropertyScopeOutput) == source.outputChannels + virtualChannels + extraOutputs else {
                throw RouteError("Core Audio returned an unexpected channel layout. Processing was not started.")
            }
            guard let created = CMProcessorCreate(48000) else { throw RouteError("Could not allocate the audio processor.") }
            processor = created
            CMProcessorSetControls(created, controls)
            let monitorOffset = monitor == nil ? UInt32.max : separateMonitor ? UInt32(source.outputChannels + virtualChannels) : 0
            CMProcessorSetRouting(created, UInt32(channel), hasVirtual ? UInt32(source.outputChannels) : UInt32.max,
                                  monitorOffset, UInt32(min(2, monitor?.outputChannels ?? 0)))
            try AudioHardware.check(AudioDeviceCreateIOProcID(aggregate, CMRender, UnsafeMutableRawPointer(created), &ioProc), "Create audio callback")
            try AudioHardware.check(AudioDeviceStart(aggregate, ioProc), "Start microphone")
        } catch {
            stop()
            throw error
        }
    }

    func update(_ controls: CMControls) {
        if let processor { CMProcessorSetControls(processor, controls) }
    }

    func meters() -> CMMeters {
        if let processor { lastMeters = CMProcessorGetMeters(processor) }
        return lastMeters
    }

    func stop() {
        if let ioProc {
            AudioDeviceStop(aggregate, ioProc)
            AudioDeviceDestroyIOProcID(aggregate, ioProc)
        }
        ioProc = nil
        if aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregate) }
        aggregate = AudioObjectID(kAudioObjectUnknown)
        if let processor { CMProcessorDestroy(processor) }
        processor = nil
    }

    deinit { stop() }
}
