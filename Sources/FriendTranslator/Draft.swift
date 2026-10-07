import Foundation

/// 手动改字后保留当时的整段文字，只接上识别结果中新说的部分。
struct DictationTranscript {
    private var recognized = ""
    private var editedPrefix: String?
    private var recognitionAtEdit = ""

    mutating func edit(_ text: String) {
        editedPrefix = text
        recognitionAtEdit = recognized
    }

    mutating func receive(_ text: String) -> String {
        recognized = text
        guard let editedPrefix else { return text }
        // 句末标点可能被识别器移到新句尾，不能把它当作旧内容的结束位置。
        let previous = Self.withoutTrailingPunctuation(recognitionAtEdit)
        let current = Self.withoutTrailingPunctuation(text)
        let difference = current.difference(from: previous)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        // 识别会回改旧字，不能按原文长度直接截取，否则会重复或漏掉新内容。
        // 末尾的替换先对应旧字，超出的文字才作为续说内容；始终对照编辑时
        // 的快照，避免临时缩短的识别结果在恢复时重复追加已修改的文字。
        var oldTail = previous.count
        var newTail = current.count
        while oldTail > 0, removed.contains(oldTail - 1) { oldTail -= 1 }
        while newTail > 0, inserted.contains(newTail - 1) { newTail -= 1 }
        let continuation = min(current.count, newTail + previous.count - oldTail)
        guard continuation < current.count else { return editedPrefix }
        var suffix = text.dropFirst(continuation)
        if let last = editedPrefix.last, Self.isPunctuation(last) {
            suffix = suffix.drop(while: Self.isPunctuation)
        }
        return editedPrefix + String(suffix)
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
    }

    private static func withoutTrailingPunctuation(_ text: String) -> [Character] {
        var result = Array(text)
        while let last = result.last, isPunctuation(last) || last.isWhitespace {
            result.removeLast()
        }
        return result
    }
}

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
