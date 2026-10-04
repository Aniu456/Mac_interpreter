@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

/// 切换语言识别窗口时，先排空当前追加，再结束或取消旧请求。
final class IncomingAudioPipe: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var lastSound: Date?

    func replace(with value: SFSpeechAudioBufferRecognitionRequest?) {
        lock.lock()
        request = value
        lock.unlock()
    }

    func append(_ buffer: AVAudioPCMBuffer, hasSound: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if hasSound { lastSound = Date() }
        request?.append(buffer)
    }

    func lastSoundTime() -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return lastSound
    }
}
