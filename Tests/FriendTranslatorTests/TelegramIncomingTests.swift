import Foundation
import Testing
import ScreenCaptureKit
@testable import FriendTranslator

@Test @MainActor func telegramCaptionsStartWithoutAMicrophoneAndPreserveHistory() async throws {
    let recognizer = TelegramTestRecognizer()
    let model = IncomingModel(recognizer: recognizer)
    model.start(device: nil, language: TargetLanguage(identifier: "ru"), allowNetwork: true, source: .telegram)
    try await telegramUntil { model.isActive }
    #expect(recognizer.microphoneStarts == 0)
    #expect(recognizer.telegramStarts == 1)
    #expect(recognizer.language?.id == "ru")
    #expect(recognizer.allowNetwork)
    let id = UUID()
    recognizer.onText?(id, "Привет", true)
    model.pauseForReply()
    recognizer.onText?(UUID(), "Не добавлять", true)
    #expect(model.captions.rows.count == 1)
    model.start(device: nil, language: TargetLanguage(identifier: "ru"), allowNetwork: true,
                source: .telegram, preserveCaptions: true)
    try await telegramUntil { model.isActive }
    #expect(recognizer.telegramStarts == 2)
    #expect(recognizer.microphoneStarts == 0)
    #expect(model.captions.rows.first?.id == id)
    model.stop()
}

@Test @MainActor func telegramFailureNeverFallsBackToMicrophone() async throws {
    let recognizer = TelegramTestRecognizer()
    recognizer.failure = "Telegram 未启动"
    let model = IncomingModel(recognizer: recognizer)
    model.start(device: nil, language: TargetLanguage(identifier: "ru"), allowNetwork: false, source: .telegram)
    try await telegramUntil { model.failure != nil }
    #expect(model.failure == "Telegram 未启动")
    #expect(!model.isActive)
    #expect(!model.isStarting)
    #expect(recognizer.microphoneStarts == 0)
    model.stop()
}

@Test @MainActor func stoppingTelegramBeforeStartupPreventsCapture() async throws {
    let recognizer = TelegramTestRecognizer()
    let model = IncomingModel(recognizer: recognizer)
    model.start(device: nil, language: TargetLanguage(identifier: "ru"), allowNetwork: false, source: .telegram)
    model.pause()
    try await Task.sleep(for: .milliseconds(20))
    #expect(recognizer.telegramStarts == 0)
    #expect(!model.isActive)
    #expect(model.isPaused)
    model.stop()
}

@MainActor private final class TelegramTestRecognizer: IncomingRecognizing {
    var onText: ((UUID, String, Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    var microphoneStarts = 0
    var telegramStarts = 0
    var language: TargetLanguage?
    var allowNetwork = false
    var failure: String?

    func start(device: AudioDevice, language: TargetLanguage, allowNetwork: Bool) async throws {
        microphoneStarts += 1
    }

    func startTelegram(language: TargetLanguage, allowNetwork: Bool) async throws {
        telegramStarts += 1
        self.language = language
        self.allowNetwork = allowNetwork
        if let failure { throw InterpreterError(failure) }
    }

    func stop() {}
}

@MainActor private func telegramUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !condition() {
        try #require(ContinuousClock.now < deadline)
        try await Task.sleep(for: .milliseconds(1))
    }
}

@Test func telegramPermissionFailureOnlyHandlesScreenCaptureDenial() {
    let denial = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
    let explained = TelegramCaptureFailure.explain(denial)
    #expect(explained is InterpreterError)
    #expect(explained.localizedDescription.contains("系统未允许当前版本"))

    let captureFailure = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.failedToStart.rawValue)
    #expect(TelegramCaptureFailure.explain(captureFailure) as NSError === captureFailure)
    let unrelated = NSError(domain: NSURLErrorDomain, code: denial.code)
    #expect(TelegramCaptureFailure.explain(unrelated) as NSError === unrelated)
    #expect(TelegramCaptureFailure.explain(CancellationError()) is CancellationError)
}
