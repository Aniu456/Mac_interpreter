import AVFoundation
import Foundation
import Speech
import Testing
import Translation
@testable import WeChatInterpreter

/// 显式启用的只读环境检查；不录音、不播放、不修改系统路由或下载资源。
@Test(.enabled(if: ProcessInfo.processInfo.environment["INTERPRETER_CHECK_ENVIRONMENT"] == "1"))
@MainActor func inspectLocalEnvironment() async throws {
    let devices = try AudioDevices.list()
    for device in devices {
        print("Device: \(device.name), builtInMic=\(device.isBuiltInMicrophone), builtInOutput=\(device.isBuiltInOutput)")
    }
    let hasMicrophone = devices.contains(where: \.isBuiltInMicrophone)
    let hasSpeaker = devices.contains(where: \.isBuiltInOutput)
    #expect(hasMicrophone)
    #expect(hasSpeaker)
    print("Chinese on-device recognition: \(SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))?.supportsOnDeviceRecognition == true)")
    for language in await SystemLanguages.installed() {
        let availability = await LanguageAvailability().status(
            from: Locale.Language(identifier: "zh-Hans"),
            to: language.localeLanguage
        )
        let voice = language.matchingIdentifier(in: AVSpeechSynthesisVoice.speechVoices().map(\.language))
            .flatMap { AVSpeechSynthesisVoice(language: $0) }
        print("Language: \(language.id), translation=\(availability), voice=\(voice?.name ?? "unavailable")")
        #expect(availability == .installed)
        #expect(voice != nil)
    }
}
