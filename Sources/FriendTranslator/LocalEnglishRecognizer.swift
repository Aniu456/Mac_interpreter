@preconcurrency import AVFoundation
import CoreML
import FluidAudio
import Foundation

/// 英文采用 Parakeet；其他语言仍由系统的对应语言模型识别。
@MainActor
final class LanguageRecognizer: IncomingRecognizing {
    var onText: ((UUID, String, Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    private let english = LocalEnglishRecognizer()
    private let system = IncomingRecognizer()
    private var active: (any IncomingRecognizing)?
    private var generation = UUID()

    init() {
        for recognizer: any IncomingRecognizing in [english, system] {
            recognizer.onText = { [weak self] in self?.onText?($0, $1, $2) }
            recognizer.onFailure = { [weak self] in self?.onFailure?($0) }
            recognizer.onStatus = { [weak self] in self?.onStatus?($0) }
        }
    }
    func start(device: AudioDevice, language: TargetLanguage, allowNetwork: Bool) async throws {
        stop()
        let token = generation
        let useEnglish = language.localeLanguage.languageCode?.identifier == "en"
            && UserDefaults.standard.object(forKey: "localEnglishRecognition") as? Bool != false
        let selected: any IncomingRecognizing = useEnglish ? english : system
        active = selected
        try await selected.start(device: device, language: language, allowNetwork: allowNetwork)
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
    }
    func startTelegram(language: TargetLanguage, allowNetwork: Bool) async throws {
        stop()
        let token = generation
        active = system
        try await system.startTelegram(language: language, allowNetwork: allowNetwork)
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
    }
    func stop() {
        generation = UUID()
        active?.stop()
        active = nil
    }
}

@MainActor
final class LocalEnglishRecognizer: IncomingRecognizing {
    var onText: ((UUID, String, Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    private let engine: StreamingEouAsrManager
    private var preparation: Task<Void, Error>?
    private var prepared = false
    private var worker: Task<Void, Never>?
    private var capture: MicrophoneCapture?
    private var continuation: AsyncStream<EnglishAudioFrame>.Continuation?
    private var generation = UUID()

    init() {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        engine = StreamingEouAsrManager(configuration: config, chunkSize: .ms320, eouDebounceMs: 400)
    }
    func start(device: AudioDevice, language: TargetLanguage, allowNetwork: Bool) async throws {
        stop()
        let token = generation
        // 等旧推理退出后才重置同一个 CoreML 会话。
        await worker?.value
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
        onStatus?("正在准备 Parakeet 本地英文模型；首次使用会下载模型…")
        if !prepared {
            if preparation == nil { preparation = Task { try await engine.loadModels() } }
            do { try await preparation?.value; prepared = true; preparation = nil }
            catch { preparation = nil; throw InterpreterError("本地英文模型加载失败，可在设置中关闭本地英文模型后重试。\(error.localizedDescription)") }
        }
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
        let granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            ? true : await AVCaptureDevice.requestAccess(for: .audio)
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
        guard granted else { throw InterpreterError("请在系统设置中允许麦克风权限。") }
        await engine.reset()
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
        let pair = AsyncStream<EnglishAudioFrame>.makeStream(bufferingPolicy: .bufferingOldest(64))
        continuation = pair.continuation
        let capture = MicrophoneCapture { [weak self] message in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.stop(); self.onFailure?(message)
            }
        }
        self.capture = capture
        worker = Task { [weak self] in
            guard let self else { return }
            var id = UUID()
            var seconds = 0.0
            do {
                for await frame in pair.stream {
                    guard self.generation == token, !Task.isCancelled else { return }
                    try await self.engine.appendAudio(frame.buffer)
                    try await self.engine.processBufferedAudio()
                    guard self.generation == token, !Task.isCancelled else { return }
                    seconds += Double(frame.buffer.frameLength) / frame.buffer.format.sampleRate
                    let text = await self.engine.getPartialTranscript()
                    guard self.generation == token, !Task.isCancelled else { return }
                    if !text.isEmpty { self.onText?(id, text, false) }
                    if await self.engine.eouDetected || seconds >= 30 {
                        let final = try await self.engine.finish()
                        guard self.generation == token, !Task.isCancelled else { return }
                        if !final.isEmpty { self.onText?(id, final, true) }
                        await self.engine.reset()
                        id = UUID(); seconds = 0
                    }
                }
            } catch {
                guard self.generation == token, !Task.isCancelled else { return }
                self.stop()
                self.onFailure?("本地英文识别中断：\(error.localizedDescription)")
            }
        }
        do {
            try await capture.start(uid: device.uid, receiveAudio: { [weak self] buffer in
                if case .dropped = pair.continuation.yield(EnglishAudioFrame(buffer: buffer)) {
                    pair.continuation.finish()
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.stop(); self.onFailure?("本地英文推理跟不上收音，已停止以避免丢字。可在设置中切换系统识别。")
                    }
                }
            })
            guard generation == token, !Task.isCancelled else { throw CancellationError() }
            onStatus?("正在用 Parakeet 本地模型听英文，音频不上传。")
        } catch {
            if generation == token { stop() }
            throw error
        }
    }
    func stop() {
        generation = UUID()
        capture?.stop(); capture = nil
        continuation?.finish(); continuation = nil
        worker?.cancel()
    }
}

/// 采集端创建独立 PCM，交出后不再修改；仅推理任务读取。
private struct EnglishAudioFrame: @unchecked Sendable { let buffer: AVAudioPCMBuffer }
