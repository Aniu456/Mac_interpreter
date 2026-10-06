import CoreAudio
import Foundation

/// 根据 Telegram 正在使用的输入检查连接，不把系统默认麦克风当作通话输入。
enum TelegramCallRoute {
    static func outputDevice() throws -> AudioDevice {
        let devices = try AudioDevices.list()
        guard let bridge = devices.first(where: \.isTelegramBridge) else {
            throw InterpreterError("未找到 BlackHole 2ch。安装并启用后，在 Telegram 通话设置中将麦克风选为 BlackHole 2ch。")
        }
        try requireReady(for: bridge, devices: devices)
        return bridge
    }

    static func requireReady(for bridge: AudioDevice) throws {
        try requireReady(for: bridge, devices: AudioDevices.list())
    }

    private static func requireReady(for bridge: AudioDevice, devices: [AudioDevice]) throws {
        guard devices.contains(where: { $0.id == bridge.id && $0.uid == bridge.uid && $0.isTelegramBridge }) else {
            throw InterpreterError("BlackHole 2ch 已断开，已停止发送。请检查音频设备后重试。")
        }
        var inputIDs = Set<AudioObjectID>()
        var outputIDs = Set<AudioObjectID>()
        let processes = try objects(AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyProcessObjectList)
        for process in processes {
            let bundle = try AudioDevices.string(process, kAudioProcessPropertyBundleID)
            guard ["ru.keepcoder.Telegram", "org.telegram.desktop"].contains(bundle) else { continue }
            outputIDs.formUnion(try objects(process, selector: kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput))
            let running = try objects(process, selector: kAudioProcessPropertyIsRunningInput).first ?? 0
            guard running != 0 else { continue }
            let inputs = try objects(process, selector: kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeInput)
            guard !inputs.isEmpty else {
                throw InterpreterError("无法确认 Telegram 当前使用的麦克风，请检查通话音频设置后重试。")
            }
            inputIDs.formUnion(inputs)
        }
        func resolve(_ ids: Set<AudioObjectID>) throws -> [AudioDevice] {
            try ids.sorted().map { id in
                guard let device = devices.first(where: { $0.id == id }) else {
                    throw InterpreterError("Telegram 音频设备正在变化，请稍后重新检查连接。")
                }
                return device
            }
        }
        try validate(bridge: bridge, inputs: resolve(inputIDs), outputs: resolve(outputIDs))
    }

    /// 只有全部活动输入都连接到目标虚拟设备，才允许向通话播放。
    static func validate(bridge: AudioDevice, inputs: [AudioDevice], outputs: [AudioDevice]) throws {
        guard bridge.isTelegramBridge else { throw InterpreterError("通话发送必须使用 BlackHole 2ch。") }
        guard !inputs.isEmpty else {
            throw InterpreterError("尚未检测到 Telegram 启用麦克风。请接通通话、取消静音，并将 Telegram 麦克风选为 BlackHole 2ch。")
        }
        guard inputs.allSatisfy({ $0.id == bridge.id && $0.uid == bridge.uid && $0.hasInput }) else {
            let names = inputs.map(\.name).joined(separator: "、")
            throw InterpreterError("Telegram 当前麦克风：\(names)。请在 Telegram 通话设置中选择 BlackHole 2ch，再发送译文。")
        }
        // Telegram 选择 BlackHole 输入和蓝牙耳机输出时，HAL 实测会同时列出
        // BlackHole 与耳机输出。设备出现在列表里不足以认定扬声器选错。
        let hasSeparatePlayback = outputs.contains {
            $0.id != bridge.id && $0.hasOutput
                && $0.transport != kAudioDeviceTransportTypeVirtual
                && $0.transport != kAudioDeviceTransportTypeAggregate
        }
        guard !outputs.contains(where: { $0.id == bridge.id }) || hasSeparatePlayback else {
            throw InterpreterError("只检测到 BlackHole 输出连接，未检测到独立耳机或扬声器。请在 Telegram 通话设置中选择耳机或电脑扬声器作为输出，再检查连接。")
        }
    }

    private static func objects(
        _ object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) throws -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        try AudioDevices.check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size))
        guard size > 0 else { return [] }
        guard Int(size) % MemoryLayout<AudioObjectID>.size == 0 else {
            throw InterpreterError("系统返回了无法识别的音频连接信息。")
        }
        var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = result.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer.baseAddress!)
        }
        try AudioDevices.check(status)
        return Array(result.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
}
