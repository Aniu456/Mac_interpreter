import CoreAudio
import Testing
@testable import FriendTranslator

private let callBridge = AudioDevice(id: 73, uid: "BlackHole2ch_UID", name: "BlackHole 2ch", hasInput: true, hasOutput: true, transport: kAudioDeviceTransportTypeVirtual)
private let callMic = AudioDevice(id: 97, uid: "mic", name: "电脑麦克风", hasInput: true, hasOutput: false, transport: kAudioDeviceTransportTypeBuiltIn)
private let callSpeaker = AudioDevice(id: 90, uid: "speaker", name: "电脑扬声器", hasInput: false, hasOutput: true, transport: kAudioDeviceTransportTypeBuiltIn)

@Test func telegramRouteAcceptsOnlyBridgeInput() throws {
    try TelegramCallRoute.validate(bridge: callBridge, inputs: [callBridge], outputs: [callSpeaker])
}

@Test func telegramRouteRejectsMissingOrMixedMicrophones() {
    for inputs in [[], [callMic], [callBridge, callMic]] {
        #expect(throws: InterpreterError.self) {
            try TelegramCallRoute.validate(bridge: callBridge, inputs: inputs, outputs: [callSpeaker])
        }
    }
}

@Test func telegramRouteRejectsFeedbackAndPhysicalDestination() {
    #expect(throws: InterpreterError.self) {
        try TelegramCallRoute.validate(bridge: callBridge, inputs: [callBridge], outputs: [callBridge])
    }
    #expect(throws: InterpreterError.self) {
        try TelegramCallRoute.validate(bridge: callSpeaker, inputs: [callBridge], outputs: [callSpeaker])
    }
}

@Test func telegramBridgeRequiresStableIdentityAndBothDirections() {
    let wrongUID = AudioDevice(id: 73, uid: "different", name: "BlackHole 2ch", hasInput: true, hasOutput: true, transport: kAudioDeviceTransportTypeVirtual)
    let outputOnly = AudioDevice(id: 73, uid: "BlackHole2ch_UID", name: "BlackHole 2ch", hasInput: false, hasOutput: true, transport: kAudioDeviceTransportTypeVirtual)
    #expect(!wrongUID.isTelegramBridge)
    #expect(!outputOnly.isTelegramBridge)
    #expect(throws: InterpreterError.self) {
        try TelegramCallRoute.validate(bridge: callBridge, inputs: [wrongUID], outputs: [callSpeaker])
    }
}


@Test func telegramRouteAllowsBridgeListedAlongsideActualHeadphones() throws {
    // 来自本次失败现场的设备拓扑：输入 73，输出 73 和 132。
    let headphones = AudioDevice(id: 132, uid: "test-headphones-output", name: "QCY H3 Pro", hasInput: false, hasOutput: true, transport: kAudioDeviceTransportTypeBluetooth)
    try TelegramCallRoute.validate(bridge: callBridge, inputs: [callBridge], outputs: [callBridge, headphones])
    try TelegramCallRoute.validate(bridge: callBridge, inputs: [callBridge], outputs: [callBridge, callSpeaker])
    #expect(throws: InterpreterError.self) {
        try TelegramCallRoute.validate(bridge: callBridge, inputs: [callMic], outputs: [callBridge, headphones])
    }
}

@Test func telegramRouteDoesNotMistakeAnotherVirtualOutputForHeadphones() {
    let virtualOutput = AudioDevice(id: 200, uid: "virtual-output", name: "Virtual Output", hasInput: true, hasOutput: true, transport: kAudioDeviceTransportTypeVirtual)
    #expect(throws: InterpreterError.self) {
        try TelegramCallRoute.validate(bridge: callBridge, inputs: [callBridge], outputs: [callBridge, virtualOutput])
    }
}
