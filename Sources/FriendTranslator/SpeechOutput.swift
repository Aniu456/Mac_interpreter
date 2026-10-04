@preconcurrency import AVFoundation
import Foundation

/// AVSpeech 回调的 PCM 经复制后，只由主线程消费。
private struct SpeechBuffer: @unchecked Sendable {
    let pcm: AVAudioPCMBuffer

    init?(_ source: AVAudioPCMBuffer) {
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return nil }
        copy.frameLength = source.frameLength
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let outputs = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (input, output) in zip(inputs, outputs) {
            if let from = input.mData, let to = output.mData {
                memcpy(to, from, Int(input.mDataByteSize))
            }
        }
        pcm = copy
    }
}

@MainActor
protocol SpeechPlaying: AnyObject {
    var onFinished: (() -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    var onPlaybackStarted: (() -> Void)? { get set }
    func speak(_ text: String, language: TargetLanguage, voiceID: String?, device: AudioDevice) throws
    func stop()
}

@MainActor
final class SpeechOutput: SpeechPlaying {
    var onFinished: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onPlaybackStarted: (() -> Void)?
    private var synthesizer: AVSpeechSynthesizer?
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var buffers: [AVAudioPCMBuffer] = []
    private var generation = UUID()
    private var timeout: Task<Void, Never>?
    private var deviceWatch: Task<Void, Never>?
    private var configurationObserver: NSObjectProtocol?
    private var duration: Double = 0
    private var outputDevice: AudioDevice?
    private var sourceLevel = AudioSignalLevel()

    func speak(_ text: String, language: TargetLanguage, voiceID: String?, device: AudioDevice) throws {
        stop()
        let token = generation
        guard !text.isEmpty, text.count <= 3000 else { throw InterpreterError("译文为空或过长，请分成短句。") }
        let voice: AVSpeechSynthesisVoice
        if let voiceID {
            guard let selected = AVSpeechSynthesisVoice(identifier: voiceID),
                  language.matchingIdentifier(in: [selected.language]) != nil else {
                throw InterpreterError("所选音色已不可用或与译文语言不符，请刷新后重新选择播报音色。")
            }
            voice = selected
        } else {
            guard let identifier = language.matchingIdentifier(in: AVSpeechSynthesisVoice.speechVoices().map(\.language)),
                  let automatic = AVSpeechSynthesisVoice(language: identifier) else {
                throw InterpreterError("未安装\(language.title)语音。请到系统设置 → 辅助功能 → 朗读内容 → 系统声音中下载。")
            }
            voice = automatic
        }
        guard try AudioDevices.list().contains(where: { $0.uid == device.uid && $0.id == device.id && $0.isBuiltInOutput }) else {
            throw InterpreterError("找不到内建扬声器，请检查设备后重试。")
        }
        let audioEngine = AVAudioEngine()
        try AudioDevices.bind(audioEngine.outputNode, to: device.id)
        engine = audioEngine
        outputDevice = device
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main
        ) { @Sendable [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.fail("音频路由发生变化，已停止播放。请检查设备后重试。")
            }
        }
        let speech = AVSpeechSynthesizer()
        synthesizer = speech
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speech.write(utterance) { @Sendable [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else {
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.fail("语音合成返回了不支持的音频格式。")
                }
                return
            }
            let ended = pcm.frameLength == 0
            let owned = ended ? nil : SpeechBuffer(pcm)
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                if ended {
                    do { try self.play(token: token) } catch { self.fail(error.localizedDescription) }
                } else if let owned {
                    self.duration += Double(owned.pcm.frameLength) / owned.pcm.format.sampleRate
                    guard self.duration <= 180 else { self.fail("语音超过三分钟，请缩短中文内容。"); return }
                    self.buffers.append(owned.pcm)
                    self.sourceLevel.observe(owned.pcm)
                } else {
                    self.fail("无法分配语音缓冲区。")
                }
            }
        }
        armTimeout(seconds: 30, token: token, message: "语音合成超时，请检查系统声音是否已下载。")
        deviceWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, self.generation == token else { return }
                do {
                    guard try AudioDevices.list().contains(where: { $0.uid == device.uid && $0.id == device.id }) else {
                        self.fail("输出设备已断开，已停止播放。"); return
                    }
                } catch { self.fail(error.localizedDescription); return }
            }
        }
    }

    func stop() {
        generation = UUID()
        timeout?.cancel()
        timeout = nil
        deviceWatch?.cancel()
        deviceWatch = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        buffers.removeAll()
        duration = 0
        outputDevice = nil
        sourceLevel = AudioSignalLevel()
    }

    private func play(token: UUID) throws {
        guard let first = buffers.first, let engine, let outputDevice else { throw InterpreterError("系统未生成语音，请检查声音下载。") }
        guard sourceLevel.samples > 0, sourceLevel.hasSignal else {
            throw InterpreterError("系统合成的语音未检测到有效声音，请更换系统声音后重试。")
        }
        let node = AVAudioPlayerNode()
        player = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: first.format)
        for (index, buffer) in buffers.enumerated() {
            guard buffer.format == first.format else { throw InterpreterError("语音格式发生变化，请重试。") }
            if index == buffers.count - 1 {
                node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.generation == token else { return }
                        self.stop()
                        self.onFinished?()
                    }
                }
            } else {
                node.scheduleBuffer(buffer)
            }
        }
        engine.prepare()
        try engine.start()
        try AudioDevices.verifyBinding(engine.outputNode, to: outputDevice.id)
        node.play()
        onPlaybackStarted?()
        armTimeout(seconds: duration + 10, token: token, message: "音频播放未正常结束，请检查输出设备。")
    }

    private func armTimeout(seconds: Double, token: UUID, message: String) {
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.fail(message)
        }
    }

    private func fail(_ message: String) {
        stop()
        onFailure?(message)
    }
}
