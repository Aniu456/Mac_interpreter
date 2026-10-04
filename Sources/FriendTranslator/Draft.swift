import Foundation

/// 中文修改后，之前的译文必须失效；旧异步结果不得覆盖新一轮输入。
struct Draft: Equatable {
    private(set) var generation = UUID()
    private(set) var chinese = ""
    private(set) var translation = ""
    private(set) var sent = false

    mutating func edit(_ text: String) {
        guard chinese != text else { return }
        chinese = text
        invalidate()
    }

    mutating func invalidate() {
        generation = UUID()
        translation = ""
        sent = false
    }

    mutating func commit(_ translation: String, generation expected: UUID) -> Bool {
        guard generation == expected else { return false }
        let text = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        self.translation = text
        sent = false
        return true
    }

    var canPlay: Bool { !translation.isEmpty }

    mutating func markSent() { sent = true }
}
