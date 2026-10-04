import CoreAudio
import Foundation
import Testing
@testable import WeChatInterpreter

private let japaneseVoice = SpeechVoice(id: "test-ja", name: "Kyoko", languageIdentifier: "ja-JP")
private let polishVoice = SpeechVoice(id: "test-pl", name: "Zosia", languageIdentifier: "pl-PL")

@Test func voicesAreFilteredByLanguageAndKeepDistinctQualities() {
    let enhanced = SpeechVoice(id: "test-ja-enhanced", name: "Kyoko", languageIdentifier: "ja-JP", quality: "增强")
    let matches = SpeechVoice.matching([polishVoice, japaneseVoice, enhanced], language: TargetLanguage(identifier: "ja"))
    #expect(Set(matches.map(\.id)) == [japaneseVoice.id, enhanced.id])
    #expect(japaneseVoice.title != enhanced.title)
}

@Test @MainActor func voicePreferencePersistsPerLanguageAndRecoversAfterDownload() async throws {
    let suite = "WeChatInterpreterTests.voices.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let japanese = TargetLanguage(identifier: "ja")
    let polish = TargetLanguage(identifier: "pl")
    var voices = [japaneseVoice, polishVoice]
    let model = AppModel(listDevices: { [] }, listLanguages: { [japanese, polish] },
                         listVoices: { voices }, voicePreferences: preferences)
    await model.refreshLanguages()
    #expect(model.availableVoices == [japaneseVoice])
    model.selectVoice(japaneseVoice.id)
    #expect(model.selectedVoiceID == japaneseVoice.id)
    model.selectVoice(polishVoice.id) // 外语音色不能用于当前译文。
    #expect(model.selectedVoiceID == japaneseVoice.id)
    model.selectLanguage(polish)
    #expect(model.selectedVoiceID == nil)
    model.selectVoice(polishVoice.id)
    model.selectLanguage(japanese)
    #expect(model.selectedVoiceID == japaneseVoice.id)
    voices = [polishVoice]
    model.refreshVoices()
    #expect(model.availableVoices.isEmpty)
    #expect(model.selectedVoiceID == nil)
    voices.append(japaneseVoice)
    model.refreshVoices()
    #expect(model.selectedVoiceID == japaneseVoice.id)

    let reopened = AppModel(listDevices: { [] }, listLanguages: { [japanese, polish] },
                            listVoices: { voices }, voicePreferences: preferences)
    await reopened.refreshLanguages()
    #expect(reopened.selectedVoiceID == japaneseVoice.id)
    reopened.selectVoice(nil)
    reopened.refreshVoices()
    #expect(reopened.selectedVoiceID == nil)
}

@Test @MainActor func selectedVoiceReachesPlaybackAndCanChangeForReplay() async throws {
    let suite = "WeChatInterpreterTests.playbackVoice.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite) }
    let japanese = TargetLanguage(identifier: "ja")
    let player = VoiceRecordingPlayer()
    let model = AppModel(speech: player, listDevices: {
        [AudioDevice(id: 1, uid: "test-speaker", name: "内建扬声器", hasInput: false,
                     hasOutput: true, transport: kAudioDeviceTransportTypeBuiltIn)]
    }, listLanguages: { [japanese] }, listVoices: { [japaneseVoice] }, voicePreferences: preferences)
    await model.refreshLanguages()
    model.selectVoice(japaneseVoice.id)
    model.editChinese("你好")
    model.translate()
    await model.runTranslation(language: japanese) { _, _ in "こんにちは" }
    #expect(player.voiceIDs == [japaneseVoice.id])
    model.selectVoice(nil) // 正在合成期间不切换音色。
    #expect(model.selectedVoiceID == japaneseVoice.id)
    player.onFailure?("测试播放失败")
    model.selectVoice(nil)
    model.playTranslation()
    #expect(player.voiceIDs == [japaneseVoice.id, nil])
    model.stop()
}

@MainActor private final class VoiceRecordingPlayer: SpeechPlaying {
    var onFinished: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onPlaybackStarted: (() -> Void)?
    var voiceIDs: [String?] = []
    func speak(_ text: String, language: TargetLanguage, voiceID: String?, device: AudioDevice) throws {
        voiceIDs.append(voiceID)
    }
    func stop() {}
}
