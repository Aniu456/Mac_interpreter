import Foundation
import Testing
@testable import FriendTranslator

@Test func incomingOriginalAndChineseRemainPaired() {
    var captions = IncomingCaptions()
    let first = UUID()
    let second = UUID()
    captions.update(id: first, text: "Hello")
    captions.update(id: second, text: "See you tomorrow")
    captions.commit(id: second, revision: 1, chinese: "明天见")
    captions.commit(id: first, revision: 1, chinese: "你好")
    #expect(captions.rows[0].original == "Hello")
    #expect(captions.rows[0].chinese == "你好")
    #expect(captions.rows[1].chinese == "明天见")
}

@Test func partialTranslationsProgressWithoutOverwritingNewerChinese() {
    var captions = IncomingCaptions()
    let id = UUID()
    captions.update(id: id, text: "Good")
    captions.update(id: id, text: "Good morning")
    captions.commit(id: id, revision: 1, chinese: "好")
    #expect(captions.rows[0].translatedRevision == 1)
    captions.commit(id: id, revision: 2, chinese: "早上好")
    captions.commit(id: id, revision: 1, chinese: "好")
    #expect(captions.rows[0].chinese == "早上好")
    #expect(captions.rows[0].original == "Good morning")
}

@Test func incomingHistoryIsBoundedAndExpiredResultsAreIgnored() {
    var captions = IncomingCaptions()
    let old = UUID()
    captions.update(id: old, text: "old")
    for number in 1...7 { captions.update(id: UUID(), text: "\(number)") }
    captions.commit(id: old, revision: 1, chinese: "过期")
    #expect(captions.rows.count == 6)
    #expect(captions.rows.first?.original == "2")
    #expect(captions.rows.allSatisfy { $0.chinese.isEmpty })
}
