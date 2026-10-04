@preconcurrency import Speech
import Foundation

enum SpeechAuthorization {
    typealias Reply = @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void

    // TCC 可从任意队列回调；必须在非主 actor 上构造回调。
    // register 允许测试使用后台回调，不触发真实权限或采集音频。
    nonisolated static func request(
        using register: @Sendable (@escaping Reply) -> Void = { SFSpeechRecognizer.requestAuthorization($0) }
    ) async throws -> SFSpeechRecognizerAuthorizationStatus {
        let reply = PendingReply()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard reply.install(continuation) else { return }
                register { status in reply.finish(.success(status)) }
            }
        } onCancel: {
            reply.finish(.failure(CancellationError()))
        }
    }

    // 权限回复可能晚于停止或超时；只恢复一次 continuation，并释放取消的等待者。
    private final class PendingReply: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<SFSpeechRecognizerAuthorizationStatus, Error>?
        private var continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Error>?

        func install(_ continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Error>) -> Bool {
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
                return false
            }
            self.continuation = continuation
            lock.unlock()
            return true
        }

        func finish(_ result: Result<SFSpeechRecognizerAuthorizationStatus, Error>) {
            lock.lock()
            guard self.result == nil else { lock.unlock(); return }
            self.result = result
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(with: result)
        }
    }
}
