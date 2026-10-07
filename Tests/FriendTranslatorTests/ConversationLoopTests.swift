import CoreAudio
import Foundation
import Testing
@testable import FriendTranslator

@Test @MainActor func editingChineseDuringDictationKeepsRecordingAndSendsCorrectedText() async throws {
    let fixture = await ConversationFixture()
    let model = fixture.model
    model.selectFriendAudioSource(.telegram)
    model.startRecording()
    try await loopUntil { model.phase == .listening }
    fixture.microphone.onPartial?("明天去北经")
    #expect(model.canEditChinese)
    model.editChinese("后天去北京")
    #expect(model.phase == .listening)
    #expect(fixture.microphone.running)
    fixture.microphone.onPartial?("明天去北京吃饭")
    #expect(model.draft.chinese == "后天去北京吃饭")
    model.finishRecording()
    model.editChinese("后天去北京喝茶")
    fixture.microphone.complete("明天去北京吃饭")
    #expect(model.phase == .translating)
    #expect(!model.canEditChinese)
    model.editChinese("不能在发送途中修改")
    await model.runTranslation(language: .english) { text, _ in
        #expect(text == "后天去北京喝茶")
        return "Tea in Beijing the day after tomorrow."
    }
    #expect(fixture.speech.texts == ["Tea in Beijing the day after tomorrow."])
    #expect(fixture.speech.device == telegramTestBridge)
    #expect(model.isSendingToTelegram)
    model.stop()

    model.startRecording()
    try await loopUntil { model.phase == .listening }
    fixture.microphone.onPartial?("新的回复")
    #expect(model.draft.chinese == "新的回复")
    model.stop()
}

@Test @MainActor func listeningTogglePausesAndResumesWithoutClearingText() async throws {
    let fixture = await ConversationFixture()
    let model = fixture.model
    model.editChinese("明天见")
    model.toggleIncoming()
    try await loopUntil { model.incoming.isActive }
    let rowID = UUID()
    fixture.friend.onText?(rowID, "See you tomorrow.", true)

    model.toggleIncoming()
    #expect(model.incoming.isPaused)
    #expect(!model.isHearingFriend)
    #expect(!fixture.friend.running)
    #expect(model.draft.chinese == "明天见")
    #expect(model.incoming.captions.rows.first?.id == rowID)

    model.toggleIncoming()
    try await loopUntil { model.incoming.isActive }
    #expect(!model.incoming.isPaused)
    #expect(fixture.friend.starts == 2)
    #expect(model.incoming.captions.rows.first?.original == "See you tomorrow.")
    model.stop()
}

@Test @MainActor func listeningToggleCancelsStartupAndCannotInterruptReply() async throws {
    let fixture = await ConversationFixture()
    let model = fixture.model
    model.toggleIncoming()
    #expect(model.incoming.isStarting)
    model.toggleIncoming()
    try await Task.sleep(for: .milliseconds(15))
    #expect(model.incoming.isPaused)
    #expect(!model.isHearingFriend)
    #expect(!fixture.friend.running)

    model.startRecording()
    try await loopUntil { model.phase == .listening }
    model.toggleIncoming()
    #expect(model.phase == .listening)
    #expect(!model.isHearingFriend)
    #expect(fixture.microphone.running)
    model.stop()
}

@Test @MainActor func threeRepliesPauseCaptureAndResumeFriendWithHistory() async throws {
    let fixture = await ConversationFixture()
    let model = fixture.model
    model.startIncoming()
    try await loopUntil { model.incoming.isActive }
    let rowID = UUID()
    fixture.friend.onText?(rowID, "How are you?", true)

    for turn in 1...3 {
        model.startRecording()
        #expect(!model.incoming.isActive)
        #expect(model.incoming.isPaused)
        try await loopUntil { model.phase == .listening }
        #expect(fixture.microphone.starts == turn)
        #expect(fixture.microphone.device == builtInTestMic)
        #expect(!fixture.friend.running)
        fixture.microphone.onPartial?("你好")
        model.finishRecording()
        #expect(model.phase == .finalizing)
        fixture.microphone.complete("你好")
        #expect(model.phase == .translating)
        await model.runTranslation(language: .english) { text, language in
            #expect(text == "你好")
            #expect(language == .english)
            return "Hello."
        }
        #expect(fixture.speech.texts.count == turn)
        #expect(fixture.speech.device == builtInTestSpeaker)
        #expect(model.phase == .synthesizing)
        model.startIncoming() // 手动点击也不能在合成或播放时重新收音。
        #expect(fixture.friend.starts == turn)
        fixture.speech.begin()
        #expect(model.phase == .speaking)
        #expect(!fixture.microphone.running)
        #expect(!fixture.friend.running)
        fixture.speech.complete()
        #expect(model.phase == .returningToFriend)
        #expect(!model.incoming.isActive)
        try await loopUntil { model.incoming.isActive }
        #expect(fixture.friend.starts == turn + 1)
        #expect(model.incoming.captions.rows.first?.id == rowID)
        #expect(model.incoming.captions.rows.first?.original == "How are you?")
    }
    model.stop()
}

@Test @MainActor func replyCanStartWithoutPriorFriendListening() async throws {
    let fixture = await ConversationFixture()
    fixture.model.editChinese("明天见")
    fixture.model.translate()
    await fixture.model.runTranslation(language: .english) { _, _ in "See you tomorrow." }
    #expect(fixture.speech.texts == ["See you tomorrow."])
    fixture.speech.begin()
    fixture.speech.complete()
    try await loopUntil { fixture.model.incoming.isActive }
    #expect(fixture.friend.device == builtInTestMic)
    #expect(fixture.model.draft.canPlay)

    fixture.model.playTranslation()
    #expect(!fixture.model.incoming.isActive)
    #expect(fixture.speech.texts.count == 2)
    fixture.speech.begin()
    fixture.speech.complete()
    try await loopUntil { fixture.model.incoming.isActive }
    fixture.model.stop()
}

@Test @MainActor func stopDuringPlaybackIgnoresLateCompletion() async throws {
    let fixture = await ConversationFixture()
    await fixture.preparePlayback()
    fixture.speech.begin()
    fixture.model.stop()
    fixture.speech.complete()
    try await Task.sleep(for: .milliseconds(25))
    #expect(fixture.model.phase == .idle)
    #expect(!fixture.model.incoming.isActive)
    #expect(!fixture.model.incoming.isStarting)
    #expect(fixture.friend.starts == 0)
    #expect(!fixture.model.draft.canPlay)
}

@Test @MainActor func stopDuringPlaybackCooldownCancelsAutomaticListening() async throws {
    let fixture = await ConversationFixture()
    await fixture.preparePlayback()
    fixture.speech.begin()
    fixture.speech.complete()
    #expect(fixture.model.phase == .returningToFriend)
    fixture.model.stop()
    try await Task.sleep(for: .milliseconds(25))
    #expect(fixture.friend.starts == 0)
    #expect(fixture.model.phase == .idle)
}

@Test @MainActor func languageChangeCancelsResumeAndInvalidatesOldOutput() async throws {
    let fixture = await ConversationFixture()
    await fixture.preparePlayback()
    fixture.speech.begin()
    fixture.speech.complete()
    fixture.model.selectLanguage(.russian)
    try await Task.sleep(for: .milliseconds(25))
    #expect(fixture.friend.starts == 0)
    #expect(fixture.model.language == .russian)
    #expect(fixture.model.draft.translation.isEmpty)
    fixture.model.startIncoming()
    try await loopUntil { fixture.model.incoming.isActive }
    #expect(fixture.friend.language == .russian)
    fixture.model.stop()
}

@Test @MainActor func stoppedTranslationCannotStartPlayback() async throws {
    let fixture = await ConversationFixture()
    fixture.model.editChinese("你好")
    fixture.model.translate()
    var result: CheckedContinuation<String, Never>?
    let work = Task { @MainActor in
        await fixture.model.runTranslation(language: .english) { _, _ in
            await withCheckedContinuation { result = $0 }
        }
    }
    try await loopUntil { result != nil }
    fixture.model.stop()
    result?.resume(returning: "Hello.")
    await work.value
    #expect(fixture.speech.texts.isEmpty)
    #expect(fixture.model.draft.translation.isEmpty)
    #expect(fixture.friend.starts == 0)
}

@Test @MainActor func playbackFailureKeepsTranslationForRetryWithoutOpeningMic() async throws {
    let fixture = await ConversationFixture()
    await fixture.preparePlayback()
    fixture.speech.begin()
    fixture.speech.onFailure?("测试播放失败")
    #expect(fixture.model.failure == "测试播放失败")
    #expect(fixture.model.draft.translation == "Hello.")
    #expect(fixture.model.draft.canPlay)
    #expect(fixture.friend.starts == 0)
    fixture.model.playTranslation()
    #expect(fixture.model.failure == nil)
    fixture.speech.begin()
    fixture.speech.complete()
    try await loopUntil { fixture.model.incoming.isActive }
    fixture.model.stop()
}

@Test @MainActor func chineseFailureKeepsPartialTextAndCanReturnToFriend() async throws {
    let fixture = await ConversationFixture()
    fixture.model.startRecording()
    try await loopUntil { fixture.model.phase == .listening }
    fixture.microphone.onPartial?("你好")
    fixture.microphone.onFailure?("测试识别失败")
    #expect(fixture.model.draft.chinese == "你好")
    #expect(fixture.speech.texts.isEmpty)
    fixture.model.startIncoming()
    try await loopUntil { fixture.model.incoming.isActive }
    #expect(fixture.model.failure == nil)
    fixture.model.stop()
}

@MainActor private final class ConversationFixture {
    let friend = LoopFriendRecognizer()
    let microphone = LoopMicrophoneRecognizer()
    let speech = LoopSpeechPlayer()
    let model: AppModel

    init(telegramOutput: @escaping () throws -> AudioDevice = { telegramTestBridge }) async {
        model = AppModel(
            incoming: IncomingModel(recognizer: friend), microphone: microphone, speech: speech,
            listDevices: { [builtInTestMic, builtInTestSpeaker, telegramTestBridge] },
            listLanguages: { [.english, .russian] }, listVoices: { [] }, playbackCooldown: .milliseconds(10),
            telegramOutput: telegramOutput
        )
        await model.refreshLanguages()
    }

    func preparePlayback() async {
        model.editChinese("你好")
        model.translate()
        await model.runTranslation(language: .english) { _, _ in "Hello." }
    }
}

@MainActor private final class LoopFriendRecognizer: IncomingRecognizing {
    var onText: ((UUID, String, Bool) -> Void)?
    var onFailure: ((String) -> Void)?
    var onStatus: ((String) -> Void)?
    var starts = 0
    var running = false
    var device: AudioDevice?
    var language: TargetLanguage?

    func start(device: AudioDevice, language: TargetLanguage, allowNetwork: Bool) async throws {
        starts += 1
        running = true
        self.device = device
        self.language = language
    }
    func startTelegram(language: TargetLanguage, allowNetwork: Bool) async throws {
        starts += 1
        running = true
        device = nil
        self.language = language
    }
    func stop() { running = false }
}

@MainActor private final class LoopMicrophoneRecognizer: MicrophoneRecognizing {
    var onProgress: ((String) -> Void)?
    var onPartial: ((String) -> Void)?
    var onFinished: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    var starts = 0
    var running = false
    var device: AudioDevice?

    func start(device: AudioDevice, allowNetwork: Bool) async throws {
        starts += 1
        running = true
        self.device = device
    }
    func finish() { running = false }
    func cancel() { running = false }
    func complete(_ text: String) {
        running = false
        onFinished?(text)
    }
}

@MainActor private final class LoopSpeechPlayer: SpeechPlaying {
    var onFinished: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onPlaybackStarted: (() -> Void)?
    var texts: [String] = []
    var device: AudioDevice?
    func speak(_ text: String, language: TargetLanguage, voiceID: String?, rate: Float, device: AudioDevice) throws {
        texts.append(text)
        self.device = device
    }
    func stop() {}
    func begin() { onPlaybackStarted?() }
    func complete() { onFinished?() }
}

private let builtInTestMic = AudioDevice(id: 1, uid: "test-mic", name: "测试麦克风", hasInput: true, hasOutput: false, transport: kAudioDeviceTransportTypeBuiltIn)
private let builtInTestSpeaker = AudioDevice(id: 2, uid: "test-speaker", name: "测试扬声器", hasInput: false, hasOutput: true, transport: kAudioDeviceTransportTypeBuiltIn)

@MainActor private func loopUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while !condition() {
        try #require(ContinuousClock.now < deadline, "对话状态未在限定时间内改变")
        try await Task.sleep(for: .milliseconds(1))
    }
}


private let telegramTestBridge = AudioDevice(id: 73, uid: "BlackHole2ch_UID", name: "BlackHole 2ch", hasInput: true, hasOutput: true, transport: kAudioDeviceTransportTypeVirtual)

@Test @MainActor func telegramChineseReplyUsesBridgeAndResumesCaptions() async throws {
    let fixture = await ConversationFixture()
    let model = fixture.model
    model.selectLanguage(.russian)
    model.selectFriendAudioSource(.telegram)
    model.startIncoming()
    try await loopUntil { model.incoming.isActive }
    let row = UUID()
    fixture.friend.onText?(row, "Привет", true)
    model.startRecording()
    try await loopUntil { model.phase == .listening }
    #expect(fixture.microphone.device == builtInTestMic)
    model.finishRecording()
    fixture.microphone.complete("你好")
    await model.runTranslation(language: .russian) { _, _ in "Привет" }
    #expect(fixture.speech.device == telegramTestBridge)
    #expect(model.isSendingToTelegram)
    #expect(!fixture.friend.running)
    fixture.speech.begin()
    fixture.speech.complete()
    try await loopUntil { model.incoming.isActive }
    #expect(fixture.friend.device == nil)
    #expect(model.incoming.captions.rows.first?.id == row)
    #expect(!model.isSendingToTelegram)
    model.stop()
}

@Test @MainActor func telegramDisconnectedKeepsTranslationAndAllowsLocalPreview() async throws {
    var connected = false
    let fixture = await ConversationFixture(telegramOutput: {
        guard connected else { throw InterpreterError("请切换 Telegram 麦克风") }
        return telegramTestBridge
    })
    let model = fixture.model
    model.selectFriendAudioSource(.telegram)
    await fixture.preparePlayback()
    #expect(model.phase == .idle)
    #expect(model.failure == "请切换 Telegram 麦克风")
    #expect(model.draft.translation == "Hello.")
    #expect(fixture.speech.texts.isEmpty)
    model.playTranslation()
    #expect(fixture.speech.device == builtInTestSpeaker)
    #expect(!model.isSendingToTelegram)
    fixture.speech.begin()
    fixture.speech.complete()
    try await loopUntil { model.incoming.isActive }
    connected = true
    model.sendTranslation()
    #expect(fixture.speech.device == telegramTestBridge)
    #expect(model.isSendingToTelegram)
    #expect(model.failure == nil)
    model.stop()
}

@Test @MainActor func telegramConnectionRejectsPhysicalOutputEvenIfResolverReturnsIt() async throws {
    let fixture = await ConversationFixture(telegramOutput: { builtInTestSpeaker })
    fixture.model.selectFriendAudioSource(.telegram)
    await fixture.preparePlayback()
    #expect(fixture.speech.texts.isEmpty)
    #expect(fixture.model.failure != nil)
    #expect(fixture.model.draft.canPlay)
    fixture.model.stop()
}

@Test @MainActor func telegramRouteLossStopsPlaybackAndPreservesDraft() async throws {
    let fixture = await ConversationFixture()
    let model = fixture.model
    model.selectFriendAudioSource(.telegram)
    await fixture.preparePlayback()
    fixture.speech.begin()
    fixture.speech.onFailure?("Telegram 输入已改变")
    #expect(model.phase == .idle)
    #expect(!model.isSendingToTelegram)
    #expect(model.draft.translation == "Hello.")
    fixture.speech.complete()
    try await Task.sleep(for: .milliseconds(25))
    #expect(!model.incoming.isActive)
    model.stop()
}


@Test @MainActor func telegramConnectionRecheckClearsOldRouteFailureWithoutSending() async throws {
    var connected = false
    let fixture = await ConversationFixture(telegramOutput: {
        guard connected else { throw InterpreterError("测试旧连接错误") }
        return telegramTestBridge
    })
    let model = fixture.model
    model.selectFriendAudioSource(.telegram)
    await fixture.preparePlayback()
    #expect(model.failure == "测试旧连接错误")
    connected = true
    model.checkTelegramConnection()
    #expect(model.failure == nil)
    #expect(model.telegramConnectionStatus.contains("输入已连接"))
    #expect(model.draft.translation == "Hello.")
    #expect(fixture.speech.texts.isEmpty)
    connected = false
    model.checkTelegramConnection()
    #expect(model.failure == "测试旧连接错误")
    model.stop()
}
