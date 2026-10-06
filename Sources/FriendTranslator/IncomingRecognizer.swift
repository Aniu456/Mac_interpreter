import Foundation
@preconcurrency import AVFoundation
@preconcurrency import Speech

@MainActor
protocol IncomingRecognizing: AnyObject {
    var onText: ((UUID, String, Bool) -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    var onStatus: ((String) -> Void)? { get set }
    func start(device: AudioDevice, language: TargetLanguage, allowNetwork: Bool) async throws
    func startTelegram(language: TargetLanguage, allowNetwork: Bool) async throws
    func stop()
}

extension IncomingRecognizing {
    func startTelegram(language: TargetLanguage, allowNetwork: Bool) async throws {
        throw InterpreterError("此识别器不支持 Telegram 音频。")
    }
}

@MainActor
final class IncomingRecognizer: IncomingRecognizing {
    var onText: ((UUID, String, Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    private var telegramCapture: TelegramAudioCapture?
    private var capture: MicrophoneCapture?
    private var pipe = IncomingAudioPipe()
    private var recognizer: SFSpeechRecognizer?
    private var tasks: [UUID: SFSpeechRecognitionTask] = [:]
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var activeWindow: UUID?
    private var generation = UUID()
    private var rotation: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var cleanup: [UUID: Task<Void, Never>] = [:]
    private var allowNetwork = false

    func start(device: AudioDevice, language: TargetLanguage, allowNetwork: Bool) async throws {
        try await startCapture(device: device, language: language, allowNetwork: allowNetwork)
    }

    func startTelegram(language: TargetLanguage, allowNetwork: Bool) async throws {
        try await startCapture(device: nil, language: language, allowNetwork: allowNetwork)
    }

    private func startCapture(device: AudioDevice?, language: TargetLanguage, allowNetwork: Bool) async throws {
        try Task.checkCancellation()
        stop()
        let token = generation
        if device != nil {
            onStatus?("正在检查电脑麦克风权限…")
            let granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                ? true : await AVCaptureDevice.requestAccess(for: .audio)
            guard token == generation, !Task.isCancelled else { throw CancellationError() }
            guard granted else {
                throw InterpreterError("请在系统设置 → 隐私与安全性 → 麦克风中允许本应用。")
            }
        }
        onStatus?("正在检查朋友字幕的语音识别权限…")
        let existingAuthorization = SFSpeechRecognizer.authorizationStatus()
        let authorization = existingAuthorization == .notDetermined
            ? try await SpeechAuthorization.request() : existingAuthorization
        guard token == generation, !Task.isCancelled else { throw CancellationError() }
        guard authorization == .authorized else {
            throw InterpreterError("请在系统设置 → 隐私与安全性 → 语音识别中允许本应用。")
        }
        onStatus?("正在连接\(language.title)识别服务…")
        guard let identifier = language.matchingIdentifier(in: SFSpeechRecognizer.supportedLocales().map(\.identifier)),
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)), recognizer.isAvailable else {
            throw InterpreterError("系统暂时无法识别\(language.title)。请检查系统语音资源和网络。")
        }
        guard allowNetwork || recognizer.supportsOnDeviceRecognition else {
            throw InterpreterError("本机不支持\(language.title)离线识别。可在应用菜单的“设置”中开启“允许 Apple 在线语音识别”后重试。")
        }
        if let device {
            guard try AudioDevices.list().contains(where: {
                $0.id == device.id && $0.uid == device.uid && $0.isBuiltInMicrophone
            }) else { throw InterpreterError("找不到内建麦克风，请检查设备后重试。") }
        }
        self.recognizer = recognizer
        self.allowNetwork = allowNetwork
        pipe = IncomingAudioPipe()
        let currentPipe = pipe
        let failure: @Sendable (String) -> Void = { [weak self] message in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.fail(message)
            }
        }
        let receiveAudio: @Sendable (AVAudioPCMBuffer) -> Void = { pcm in
            var level = AudioSignalLevel()
            level.observe(pcm)
            currentPipe.append(pcm, hasSound: level.hasSignal)
        }
        do {
            openWindow()
            if let device {
                let microphoneCapture = MicrophoneCapture(onFailure: failure)
                capture = microphoneCapture
                onStatus?("正在启动内建麦克风，请让电脑听清说话声…")
                try await microphoneCapture.start(uid: device.uid, receiveAudio: receiveAudio)
            } else {
                let telegram = TelegramAudioCapture()
                telegramCapture = telegram
                onStatus?("正在连接 Telegram 音频，请允许屏幕与系统音频录制…")
                try await telegram.start(receiveAudio: receiveAudio, onFailure: failure)
            }
            guard token == generation, !Task.isCancelled else { throw CancellationError() }
        } catch {
            if token == generation { stop() }
            throw error
        }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self, self.generation == token else { return }
                if let time = self.pipe.lastSoundTime(), Date().timeIntervalSince(time) < 5 {
                    self.onStatus?(device == nil ? "已收到 Telegram 声音，正在显示原文和中文字幕。" : "电脑麦克风已收到声音，朋友原文和中文会逐步更新。")
                } else {
                    self.onStatus?(device == nil ? "等待 Telegram 声音。请接通通话，确认好友没有静音。" : "等待说话声。请靠近电脑麦克风，并确认周围声音清晰。")
                }
            }
        }
    }

    func stop() {
        generation = UUID()
        rotation?.cancel()
        rotation = nil
        monitor?.cancel()
        monitor = nil
        telegramCapture?.stop()
        telegramCapture = nil
        capture?.stop()
        capture = nil
        pipe.replace(with: nil)
        request?.endAudio()
        request = nil
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        for task in cleanup.values { task.cancel() }
        cleanup.removeAll()
        activeWindow = nil
        recognizer = nil
    }

    private func openWindow() {
        guard let recognizer else { return }
        let previousID = activeWindow
        let previousRequest = request
        let id = UUID()
        let token = generation
        let next = SFSpeechAudioBufferRecognitionRequest()
        next.shouldReportPartialResults = true
        next.requiresOnDeviceRecognition = !allowNetwork
        next.addsPunctuation = true
        next.taskHint = .dictation
        activeWindow = id
        request = next
        pipe.replace(with: next)
        previousRequest?.endAudio()
        if let previousID {
            cleanup[previousID] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self, self.generation == token else { return }
                self.tasks.removeValue(forKey: previousID)?.cancel()
                self.cleanup.removeValue(forKey: previousID)
            }
        }
        tasks[id] = recognizer.recognitionTask(with: next) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal ?? false
            let failure = error?.localizedDescription
            Task { @MainActor in
                guard let self, self.generation == token, self.tasks[id] != nil else { return }
                if let text, !text.isEmpty { self.onText?(id, text, final) }
                if final {
                    self.tasks.removeValue(forKey: id)
                    self.cleanup.removeValue(forKey: id)?.cancel()
                    if self.activeWindow == id { self.openWindow() }
                } else if let failure {
                    self.tasks.removeValue(forKey: id)
                    self.cleanup.removeValue(forKey: id)?.cancel()
                    // 已结束的窗口不打断下一窗口，原文仍保留。
                    if self.activeWindow == id {
                        self.fail("朋友语音识别中断：\(failure)。已保留字幕，可重新开启。")
                    }
                }
            }
        }
        rotation?.cancel()
        rotation = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self, self.generation == token, self.activeWindow == id else { return }
            self.openWindow()
        }
    }

    private func fail(_ message: String) {
        stop()
        onFailure?(message)
    }
}
