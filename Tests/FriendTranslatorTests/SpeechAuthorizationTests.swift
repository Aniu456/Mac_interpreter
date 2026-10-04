import Dispatch
import Foundation
import Speech
import Testing
@testable import FriendTranslator

// 从主 actor 发起、在后台回复，复现三份真实崩溃报告中的执行路径。
// 不请求权限、不录音、不发送语音。
@Test @MainActor func authorizationCanReplyFromBackgroundQueue() async throws {
    let status = try await SpeechAuthorization.request { reply in
        DispatchQueue.global().async { reply(.authorized) }
    }
    #expect(status == .authorized)
}

@Test @MainActor func deniedAuthorizationIsPreserved() async throws {
    let status = try await SpeechAuthorization.request { reply in
        DispatchQueue.global().async { reply(.denied) }
    }
    #expect(status == .denied)
}

@Test @MainActor func cancelledAuthorizationDoesNotWaitForSystemReply() async throws {
    let stored = AuthorizationReply()
    let (registered, signal) = AsyncStream<Void>.makeStream()
    let waiting = Task {
        try await SpeechAuthorization.request { reply in
            stored.set(reply)
            signal.yield(())
        }
    }
    for await _ in registered { break }
    waiting.cancel()
    await #expect(throws: CancellationError.self) { try await waiting.value }
    // 系统迟到或重复的回复都不能再次恢复已取消的 continuation。
    stored.send(.authorized)
    stored.send(.denied)
    signal.finish()
}

@Test func alreadyCancelledAuthorizationDoesNotRequestPermission() async {
    let stored = AuthorizationReply()
    let waiting = Task {
        while !Task.isCancelled { await Task.yield() }
        return try await SpeechAuthorization.request { reply in stored.set(reply) }
    }
    waiting.cancel()
    await #expect(throws: CancellationError.self) { try await waiting.value }
    #expect(!stored.wasRegistered)
}

private final class AuthorizationReply: @unchecked Sendable {
    private let lock = NSLock()
    private var reply: SpeechAuthorization.Reply?
    var wasRegistered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reply != nil
    }
    func set(_ reply: @escaping SpeechAuthorization.Reply) {
        lock.lock()
        self.reply = reply
        lock.unlock()
    }
    func send(_ status: SFSpeechRecognizerAuthorizationStatus) {
        lock.lock()
        let callback = reply
        lock.unlock()
        callback?(status)
    }
}
