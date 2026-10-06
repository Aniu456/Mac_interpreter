import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

struct InterpreterError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct AudioDevice: Identifiable, Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let hasInput: Bool
    let hasOutput: Bool
    let transport: UInt32

    var isTelegramBridge: Bool {
        uid == "BlackHole2ch_UID" && hasInput && hasOutput && transport == kAudioDeviceTransportTypeVirtual
    }

    var isBuiltInMicrophone: Bool { hasInput && transport == kAudioDeviceTransportTypeBuiltIn }
    var isBuiltInOutput: Bool { hasOutput && transport == kAudioDeviceTransportTypeBuiltIn }
}

enum AudioDevices {
    static func list() throws -> [AudioDevice] {
        var address = property(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ))
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = ids.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, bytes.baseAddress!
            )
        }
        try check(status)
        return try ids.map { id in
            AudioDevice(
                id: id,
                uid: try string(id, kAudioDevicePropertyDeviceUID),
                name: try string(id, kAudioObjectPropertyName),
                hasInput: try hasChannels(id, scope: kAudioObjectPropertyScopeInput),
                hasOutput: try hasChannels(id, scope: kAudioObjectPropertyScopeOutput),
                transport: try integer(id, kAudioDevicePropertyTransportType)
            )
        }
    }

    /// 播放监测只读取当前设备，避免反复枚举所有设备和声道配置。
    static func isConnected(_ device: AudioDevice) throws -> Bool {
        try integer(device.id, kAudioDevicePropertyDeviceIsAlive) != 0
            && string(device.id, kAudioDevicePropertyDeviceUID) == device.uid
    }

    static func bind(_ node: AVAudioIONode, to device: AudioDeviceID) throws {
        guard let unit = node.audioUnit else {
            throw InterpreterError("音频设备未就绪。")
        }
        var selected = device
        try check(AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
            0, &selected, UInt32(MemoryLayout<AudioDeviceID>.size)
        ))
        try verifyBinding(node, to: device)
    }

    static func verifyBinding(_ node: AVAudioIONode, to device: AudioDeviceID) throws {
        guard let unit = node.audioUnit else { throw InterpreterError("音频设备未就绪。") }
        var actual: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(AudioUnitGetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
            0, &actual, &size
        ))
        guard actual == device else {
            throw InterpreterError("音频设备绑定失败，已阻止使用系统默认设备。")
        }
    }

    static func check(_ status: OSStatus) throws {
        guard status == noErr else {
            throw InterpreterError("音频设备操作失败（\(status)），请检查设备连接后重试。")
        }
    }

    private static func property(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) throws -> String {
        var address = property(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value))
        guard let value else { throw InterpreterError("无法读取音频设备名称。") }
        return value.takeRetainedValue() as String
    }

    private static func integer(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) throws -> UInt32 {
        var address = property(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value))
        return value
    }

    private static func hasChannels(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> Bool {
        var address = property(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size))
        guard size >= MemoryLayout<AudioBufferList>.size else { return false }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, memory))
        return UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self))
            .contains { $0.mNumberChannels > 0 }
    }
}
