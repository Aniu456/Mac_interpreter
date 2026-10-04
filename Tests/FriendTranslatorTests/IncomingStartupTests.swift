import CoreAudio
import Foundation
import Testing
@testable import FriendTranslator

@Test @MainActor func incomingStartupTimesOutAndCanRetry() async throws {
    let recognizer = DelayedIncomingRecognizer()
    let model = IncomingModel(recognizer: recognizer, startupDeadline: .milliseconds(30))
    model.start(device: incomingTestMicrophone, language: .english, allowNetwork: false)
    try await until { recognizer.starts.count == 1 }
    try await until { !model.isStarting }
    #expect(!model.isActive)
    #expect(model.failure?.contains("启动超时") == true)
    #expect(model.failure?.contains("等待测试权限") == true)
    #expect(model.configuration == nil)

    model.start(device: incomingTestMicrophone, language: .english, allowNetwork: false)
    try await until { recognizer.starts.count == 2 }
    recognizer.complete(0, with: .success(()))
    try await until { recognizer.returned == 1 }
    #expect(model.isStarting)
    #expect(!model.isActive)
    recognizer.complete(1, with: .success(()))
    try await until { model.isActive }
    #expect(model.failure == nil)
    #expect(!model.isStarting)
    model.stop()
}

@Test @MainActor func oldIncomingFailureCannotStopNewStartup() async throws {
    let recognizer = DelayedIncomingRecognizer()
    let model = IncomingModel(recognizer: recognizer)
    model.start(device: incomingTestMicrophone, language: .english, allowNetwork: false)
    try await until { recognizer.starts.count == 1 }
    model.stop()
    model.start(device: incomingTestMicrophone, language: .russian, allowNetwork: false)
    try await until { recognizer.starts.count == 2 }
    recognizer.complete(1, with: .success(()))
    try await until { model.isActive }
    let stops = recognizer.stops
    recognizer.complete(0, with: .failure(InterpreterError("旧启动失败")))
    try await until { recognizer.returned == 2 }
    #expect(model.isActive)
    #expect(model.language == .russian)
    #expect(model.failure == nil)
    #expect(recognizer.stops == stops)
    model.stop()
}

@Test @MainActor func successfulIncomingStartupDisarmsTimeout() async throws {
    let recognizer = DelayedIncomingRecognizer()
    let model = IncomingModel(recognizer: recognizer, startupDeadline: .milliseconds(30))
    model.start(device: incomingTestMicrophone, language: .english, allowNetwork: false)
    try await until { recognizer.starts.count == 1 }
    recognizer.complete(0, with: .success(()))
    try await until { model.isActive }
    try await Task.sleep(for: .milliseconds(60))
    #expect(model.isActive)
    #expect(model.failure == nil)
    model.stop()
}

@MainActor private final class DelayedIncomingRecognizer: IncomingRecognizing {
    var onText: ((UUID, String, Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    var starts: [CheckedContinuation<Void, Error>?] = []
    var devices: [AudioDevice] = []
    var returned = 0
    var stops = 0

    func start(device: AudioDevice, language: TargetLanguage, allowNetwork: Bool) async throws {
        devices.append(device)
        defer { returned += 1 }
        onStatus?("等待测试权限")
        try await withCheckedThrowingContinuation { starts.append($0) }
    }
    func stop() { stops += 1 }
    func complete(_ index: Int, with result: Result<Void, Error>) {
        starts[index]?.resume(with: result)
        starts[index] = nil
    }
}

@MainActor private func until(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !condition() {
        try #require(ContinuousClock.now < deadline, "异步状态未在限定时间内改变")
        try await Task.sleep(for: .milliseconds(1))
    }
}

private let incomingTestMicrophone = AudioDevice(
    id: 17, uid: "BuiltInMicrophoneDevice", name: "内建麦克风",
    hasInput: true, hasOutput: false, transport: kAudioDeviceTransportTypeBuiltIn
)

@Test @MainActor func replyPausePreservesCaptionsAndBlocksAudioUntilResume() async throws {
    let recognizer = DelayedIncomingRecognizer()
    let model = IncomingModel(recognizer: recognizer)
    model.start(device: incomingTestMicrophone, language: .english, allowNetwork: false)
    try await until { recognizer.starts.count == 1 }
    recognizer.complete(0, with: .success(()))
    try await until { model.isActive }
    let id = UUID()
    recognizer.onText?(id, "Good morning", true)
    #expect(model.captions.rows.count == 1)
    model.pauseForReply()
    #expect(model.isPaused)
    #expect(!model.isActive)
    #expect(!model.isStarting)
    #expect(model.configuration == nil)
    recognizer.onText?(UUID(), "Computer playback must not become a caption", true)
    #expect(model.captions.rows.count == 1)
    #expect(model.captions.rows[0].original == "Good morning")

    model.start(device: incomingTestMicrophone, language: .english, allowNetwork: false, preserveCaptions: model.isPaused)
    try await until { recognizer.starts.count == 2 }
    recognizer.complete(1, with: .success(()))
    try await until { model.isActive }
    #expect(!model.isPaused)
    #expect(model.captions.rows.count == 1)
    #expect(model.captions.rows[0].id == id)
    #expect(recognizer.devices == [incomingTestMicrophone, incomingTestMicrophone])
    model.stop()
    #expect(!model.isPaused)
}

@Test @MainActor func replyPauseRejectsLatePermissionCompletion() async throws {
    let recognizer = DelayedIncomingRecognizer()
    let model = IncomingModel(recognizer: recognizer)
    model.start(device: incomingTestMicrophone, language: .english, allowNetwork: false)
    try await until { recognizer.starts.count == 1 }
    model.pauseForReply()
    recognizer.complete(0, with: .success(()))
    try await until { recognizer.returned == 1 }
    #expect(model.isPaused)
    #expect(!model.isActive)
    #expect(!model.isStarting)
    #expect(model.configuration == nil)
    #expect(model.failure == nil)
    model.stop()
}
