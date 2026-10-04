import CoreAudio
import Foundation
import Testing
@testable import WeChatInterpreter

@Test func editsRejectLateTranslations() {
    var draft = Draft()
    draft.edit("明天见")
    let previous = draft.generation
    draft.edit("后天见")
    let acceptedOld = draft.commit("See you tomorrow.", generation: previous)
    #expect(!acceptedOld)
    #expect(draft.translation.isEmpty)
    let acceptedNew = draft.commit("See you the day after tomorrow.", generation: draft.generation)
    #expect(acceptedNew)
}

@Test func cancellationAndLanguageChangeInvalidateOutput() {
    var draft = Draft()
    draft.edit("你好")
    let old = draft.generation
    let accepted = draft.commit("Привет!", generation: old)
    #expect(accepted)
    draft.invalidate()
    #expect(draft.chinese == "你好")
    #expect(!draft.canPlay)
    let acceptedOld = draft.commit("Hello!", generation: old)
    #expect(!acceptedOld)
}

@Test func translationCanReplayUntilEditedOrInvalidated() {
    var draft = Draft()
    draft.edit("你好")
    let acceptedEmpty = draft.commit(" \n", generation: draft.generation)
    #expect(!acceptedEmpty)
    #expect(!draft.canPlay)
    let accepted = draft.commit(" Hello! \n", generation: draft.generation)
    #expect(accepted)
    #expect(draft.translation == "Hello!")
    #expect(draft.canPlay)
    #expect(!draft.sent)
    draft.markSent()
    #expect(draft.canPlay)
    #expect(draft.sent)
    draft.edit("再见")
    #expect(!draft.canPlay)
    #expect(!draft.sent)
    let acceptedNext = draft.commit("Goodbye!", generation: draft.generation)
    #expect(acceptedNext)
    draft.invalidate()
    #expect(!draft.canPlay)
}

@Test func phoneModeOnlyUsesBuiltInDevices() {
    let blackHole = AudioDevice(id: 1, uid: "BlackHole2ch_UID", name: "BlackHole 2ch", hasInput: true, hasOutput: true, transport: kAudioDeviceTransportTypeVirtual)
    #expect(!blackHole.isBuiltInMicrophone)
    #expect(!blackHole.isBuiltInOutput)
    let aggregate = AudioDevice(id: 2, uid: "aggregate", name: "混合设备", hasInput: true, hasOutput: true, transport: kAudioDeviceTransportTypeAggregate)
    #expect(!aggregate.isBuiltInMicrophone)
    #expect(!aggregate.isBuiltInOutput)
    let mic = AudioDevice(id: 3, uid: "physical", name: "麦克风", hasInput: true, hasOutput: false, transport: kAudioDeviceTransportTypeBuiltIn)
    #expect(mic.isBuiltInMicrophone)
    #expect(!mic.isBuiltInOutput)
    let speaker = AudioDevice(id: 4, uid: "speaker", name: "扬声器", hasInput: false, hasOutput: true, transport: kAudioDeviceTransportTypeBuiltIn)
    #expect(speaker.isBuiltInOutput)
    #expect(!speaker.isBuiltInMicrophone)
    let headphones = AudioDevice(id: 5, uid: "bluetooth", name: "耳机", hasInput: true, hasOutput: true, transport: kAudioDeviceTransportTypeBluetooth)
    #expect(!headphones.isBuiltInOutput)
    #expect(!headphones.isBuiltInMicrophone)
    let usb = AudioDevice(id: 6, uid: "usb", name: "USB", hasInput: true, hasOutput: true, transport: kAudioDeviceTransportTypeUSB)
    #expect(!usb.isBuiltInMicrophone && !usb.isBuiltInOutput)
}
