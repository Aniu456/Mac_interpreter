@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

@MainActor
protocol MicrophoneRecognizing: AnyObject {
    var onProgress: ((String) -> Void)? { get set }
    var onPartial: ((String) -> Void)? { get set }
    var onFinished: ((String) -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    func start(device: AudioDevice, allowNetwork: Bool) async throws
    func finish()
    func cancel()
}

@MainActor
final class MicrophoneRecognizer: MicrophoneRecognizing {
    var onProgress: ((String) -> Void)?
    var onPartial: ((String) -> Void)?
    var onFinished: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    private var capture: MicrophoneCapture?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()

    func start(device: AudioDevice, allowNetwork: Bool) async throws {
        try Task.checkCancellation()
        cancel()
        let token = generation
        onProgress?("正在检查麦克风权限…")
        let granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            ? true : await AVCaptureDevice.requestAccess(for: .audio)
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        guard granted else { throw InterpreterError("请在系统设置 → 隐私与安全性 → 麦克风中允许此应用。") }
        onProgress?("正在检查语音识别权限…")
        let existingAuthorization = SFSpeechRecognizer.authorizationStatus()
        let authorization = existingAuthorization == .notDetermined
            ? try await SpeechAuthorization.request() : existingAuthorization
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        guard authorization == .authorized else {
            throw InterpreterError("请在系统设置 → 隐私与安全性 → 语音识别中允许此应用。")
        }
        onProgress?("正在连接中文识别服务…")
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")), recognizer.isAvailable else {
            throw InterpreterError("系统中文语音识别当前不可用。你仍可输入中文后翻译。")
        }
        guard allowNetwork || recognizer.supportsOnDeviceRecognition else {
            throw InterpreterError("本机尚不支持离线中文识别。可在应用菜单的“设置”中允许 Apple 在线识别，或直接输入中文。")
        }
        guard try AudioDevices.list().contains(where: { $0.uid == device.uid && $0.id == device.id && $0.isBuiltInMicrophone }) else {
            throw InterpreterError("找不到内建麦克风，请检查设备后重试。")
        }
        self.recognizer = recognizer
        let speechRequest = SFSpeechAudioBufferRecognitionRequest()
        speechRequest.shouldReportPartialResults = true
        speechRequest.requiresOnDeviceRecognition = !allowNetwork
        speechRequest.taskHint = .dictation
        speechRequest.addsPunctuation = true
        request = speechRequest
        let microphoneCapture = MicrophoneCapture { [weak self] message in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.cancel()
                self.onFailure?(message)
            }
        }
        capture = microphoneCapture
        recognition = recognizer.recognitionTask(with: speechRequest) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failure = error?.localizedDescription
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if let text { self.onPartial?(text) }
                if isFinal, let text {
                    self.cancel()
                    self.onFinished?(text)
                } else if let failure {
                    self.cancel()
                    self.onFailure?("语音识别未完成：\(failure)。已保留当前文字，请核对后手动翻译。")
                }
            }
        }
        do {
            onProgress?("正在启动所选麦克风…")
            try await microphoneCapture.start(uid: device.uid, request: speechRequest)
            guard token == generation, !Task.isCancelled else { throw CancellationError() }
        } catch {
            if token == generation { cancel() }
            throw error
        }
        // 系统识别适合短句，达到上限时正常结束输入并等待最终结果。
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(50))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.finish()
        }
    }

    func finish() {
        stopCapture()
        timeout?.cancel()
        let token = generation
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.cancel()
            self.onFailure?("识别未及时返回最终结果。已保留当前文字，请核对后手动翻译。")
        }
    }

    func cancel() {
        generation = UUID()
        timeout?.cancel()
        timeout = nil
        if let capture {
            capture.stop(cancelling: recognition)
        } else {
            recognition?.cancel()
        }
        recognition = nil
        request = nil
        capture = nil
        recognizer = nil
    }

    private func stopCapture() {
        capture?.stop()
    }
}
