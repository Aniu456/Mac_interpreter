@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import FriendTranslator

// 需要真实 Core Audio 设备；不合成语音，也不向通话发送声音。
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FRIEND_TRANSLATOR_AUDIO_TESTS"] == "1"), .serialized)
@MainActor
struct SpeechOutputConfigurationTests {
    @Test func bindingNotificationDoesNotCancelPreparation() async throws {
        let devices = try AudioDevices.list()
        let device = try #require(devices.first { $0.isBuiltInOutput })
        let engine = AVAudioEngine()
        try AudioDevices.bind(engine.outputNode, to: device.id)
        var received = false
        var failure: String?
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                received = true
                do {
                    try SpeechOutput.validateConfiguration(of: engine, device: device, playbackStarted: false)
                } catch {
                    failure = error.localizedDescription
                }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer); engine.stop() }
        for _ in 0..<100 {
            if received { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(received, "必须捕获真实设备绑定通知，才能验证这次误报")
        #expect(failure == nil)
        #expect(!engine.isRunning)
    }

    @Test func interruptedPlaybackStillFails() throws {
        let devices = try AudioDevices.list()
        let device = try #require(devices.first { $0.isBuiltInOutput })
        let engine = AVAudioEngine()
        try AudioDevices.bind(engine.outputNode, to: device.id)
        #expect(throws: InterpreterError.self) {
            try SpeechOutput.validateConfiguration(of: engine, device: device, playbackStarted: true)
        }
    }

    @Test func changedBindingStillFailsDuringPreparation() throws {
        let devices = try AudioDevices.list()
        let intended = try #require(devices.first { $0.isBuiltInOutput })
        let other = try #require(devices.first { $0.hasOutput && $0.id != intended.id })
        let engine = AVAudioEngine()
        try AudioDevices.bind(engine.outputNode, to: other.id)
        #expect(throws: InterpreterError.self) {
            try SpeechOutput.validateConfiguration(of: engine, device: intended, playbackStarted: false)
        }
    }
}
