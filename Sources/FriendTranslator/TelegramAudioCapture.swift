@preconcurrency import AVFoundation
import Foundation
@preconcurrency import ScreenCaptureKit

enum FriendAudioSource: String, CaseIterable, Identifiable {
    case microphone, telegram
    var id: Self { self }
    var title: String { self == .telegram ? "Telegram 通话" : "面对面 · 麦克风" }
}

/// 只采集 Telegram 桌面客户端的声音，不将自己的麦克风或其他应用混入字幕。
@MainActor
final class TelegramAudioCapture {
    private var stream: SCStream?
    private var receiver: TelegramAudioReceiver?
    private var generation = UUID()

    func start(
        receiveAudio: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
        onFailure: @escaping @Sendable (String) -> Void
    ) async throws {
        stop()
        let token = generation
        // 由实际使用的 ScreenCaptureKit 申请并判断权限，避免 CG 预检提前拦截。
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            guard generation == token, !Task.isCancelled else { throw CancellationError() }
            throw TelegramCaptureFailure.explain(error)
        }
        guard generation == token, !Task.isCancelled else { throw CancellationError() }
        let applications = content.applications.filter {
            ["ru.keepcoder.Telegram", "org.telegram.desktop"].contains($0.bundleIdentifier)
        }
        guard !applications.isEmpty else {
            throw InterpreterError("请先打开 Telegram 桌面客户端，再点击“听朋友”。当前不支持 Telegram 网页版。")
        }
        guard let display = content.displays.first else {
            throw InterpreterError("无法建立 Telegram 音频采集，请检查屏幕录制权限和显示器连接。")
        }
        let filter = SCContentFilter(display: display, including: applications, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 16_000
        configuration.channelCount = 1
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        let receiver = TelegramAudioReceiver(receiveAudio: receiveAudio, onFailure: onFailure)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: receiver)
        try stream.addStreamOutput(receiver, type: .audio, sampleHandlerQueue: receiver.queue)
        self.receiver = receiver
        self.stream = stream
        do {
            try await stream.startCapture()
            guard generation == token, !Task.isCancelled else {
                receiver.cancel()
                try? await stream.stopCapture()
                throw CancellationError()
            }
        } catch {
            if generation == token { stop() }
            throw TelegramCaptureFailure.explain(error)
        }
    }

    func stop() {
        generation = UUID()
        receiver?.cancel()
        receiver = nil
        let previous = stream
        stream = nil
        if let previous { Task { try? await previous.stopCapture() } }
    }
}

private final class TelegramAudioReceiver: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "dev.benny.interpreter.telegram-audio")
    private let lock = NSLock()
    private var active = true
    private let receiveAudio: @Sendable (AVAudioPCMBuffer) -> Void
    private let onFailure: @Sendable (String) -> Void

    init(receiveAudio: @escaping @Sendable (AVAudioPCMBuffer) -> Void, onFailure: @escaping @Sendable (String) -> Void) {
        self.receiveAudio = receiveAudio
        self.onFailure = onFailure
    }

    func cancel() {
        lock.lock()
        active = false
        lock.unlock()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        lock.lock()
        defer { lock.unlock() }
        guard active else { return }
        do {
            if let pcm = try MicrophonePCM.copy(sampleBuffer) { receiveAudio(pcm) }
        } catch {
            active = false
            onFailure("Telegram 音频读取失败：\(error.localizedDescription)")
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return }
        active = false
        onFailure("Telegram 收音已中断：\(error.localizedDescription)。请重新点击“听朋友”。")
    }
}

/// 只有 ScreenCaptureKit 明确拒绝授权时才给出权限提示，其他错误保留原始原因。
enum TelegramCaptureFailure {
    static func explain(_ error: Error) -> Error {
        let failure = error as NSError
        guard failure.domain == SCStreamErrorDomain,
              failure.code == SCStreamError.Code.userDeclined.rawValue else { return error }
        return InterpreterError("系统未允许当前版本采集 Telegram 声音。请在系统设置 → 隐私与安全性 → 录屏与系统录音中允许本应用。若开关已开启，请完全退出应用，移除权限列表中的旧条目，再添加当前使用的 App 并重新打开。")
    }
}
