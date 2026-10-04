import AVFoundation
import CoreAudio
import Foundation
import Observation
@preconcurrency import Translation

@MainActor
@Observable
final class AppModel {
    enum Phase { case idle, authorizing, listening, finalizing, translating, synthesizing, speaking, returningToFriend }
    struct TranslationWork {
        let generation: UUID
        let text: String
        let language: TargetLanguage
        let provider: TranslationProvider
    }

    private(set) var provider: TranslationProvider = .apple
    var deepSeekModel: DeepSeekModel = .flash
    var localEnglishRecognition = UserDefaults.standard.object(forKey: "localEnglishRecognition") as? Bool ?? true {
        didSet { UserDefaults.standard.set(localEnglishRecognition, forKey: "localEnglishRecognition") }
    }
    @ObservationIgnored private let ai: any AITranslating
    @ObservationIgnored private var cloudTask: Task<Void, Never>?
    private(set) var draft = Draft()
    let incoming: IncomingModel
    private(set) var phase = Phase.idle
    private(set) var devices: [AudioDevice] = []
    private(set) var status = "点击“听朋友”，查看说话原文和中文翻译。"
    private(set) var failure: String?
    private(set) var language: TargetLanguage?
    private(set) var availableLanguages: [TargetLanguage] = []
    private(set) var isRefreshingLanguages = false
    private(set) var availableVoices: [SpeechVoice] = []
    private(set) var selectedVoiceID: String?
    var microphoneID: UInt32 = 0
    var monitorID: UInt32 = 0
    var allowNetworkRecognition = UserDefaults.standard.bool(forKey: "allowNetworkRecognition") {
        didSet { UserDefaults.standard.set(allowNetworkRecognition, forKey: "allowNetworkRecognition") }
    }
    var translationConfiguration: TranslationSession.Configuration?
    @ObservationIgnored private var pendingTranslation: TranslationWork?
    @ObservationIgnored private let microphone: any MicrophoneRecognizing
    @ObservationIgnored private let speech: any SpeechPlaying
    @ObservationIgnored private let listDevices: () throws -> [AudioDevice]
    @ObservationIgnored private let listLanguages: @MainActor () async -> [TargetLanguage]
    @ObservationIgnored private let listVoices: () -> [SpeechVoice]
    @ObservationIgnored private let voicePreferences: UserDefaults
    @ObservationIgnored private let playbackCooldown: Duration
    @ObservationIgnored private var startup: Task<Void, Never>?
    @ObservationIgnored private var startupTimeout: Task<Void, Never>?
    @ObservationIgnored private var resumeListening: Task<Void, Never>?
    @ObservationIgnored private var turnID = UUID()

    var isBusy: Bool { phase != .idle }
    var microphones: [AudioDevice] { devices.filter(\.isBuiltInMicrophone) }
    var monitors: [AudioDevice] { devices.filter(\.isBuiltInOutput) }
    var selectedMicrophone: AudioDevice? { microphones.first { $0.id == microphoneID } }
    var selectedSpeaker: AudioDevice? { monitors.first { $0.id == monitorID } }
    var isHearingFriend: Bool { incoming.isActive || incoming.isStarting }
    var isCapturingChinese: Bool { phase == .authorizing || phase == .listening || phase == .finalizing }
    var displayStatus: String {
        if isHearingFriend { return incoming.status }
        if !isBusy, incoming.failure != nil { return "听朋友已停止，请处理下方提示后重试。" }
        return status
    }

    init(
        incoming: IncomingModel = IncomingModel(),
        microphone: any MicrophoneRecognizing = MicrophoneRecognizer(),
        speech: any SpeechPlaying = SpeechOutput(),
        listDevices: @escaping () throws -> [AudioDevice] = AudioDevices.list,
        listLanguages: @escaping @MainActor () async -> [TargetLanguage] = SystemLanguages.installed,
        listVoices: @escaping () -> [SpeechVoice] = SpeechVoice.available,
        voicePreferences: UserDefaults = .standard,
        playbackCooldown: Duration = .milliseconds(500),
        ai: any AITranslating = AITranslator()
    ) {
        self.ai = ai
        self.incoming = incoming
        self.microphone = microphone
        self.speech = speech
        self.listDevices = listDevices
        self.listLanguages = listLanguages
        self.listVoices = listVoices
        self.voicePreferences = voicePreferences
        self.playbackCooldown = playbackCooldown
        microphone.onProgress = { [weak self] message in
            guard let self, self.isCapturingChinese else { return }
            self.status = message
        }
        microphone.onPartial = { [weak self] text in
            guard let self, self.isCapturingChinese else { return }
            self.draft.edit(text)
        }
        microphone.onFinished = { [weak self] text in
            guard let self, self.isCapturingChinese else { return }
            self.startupTimeout?.cancel()
            self.startupTimeout = nil
            self.draft.edit(text)
            self.phase = .idle
            self.translate()
        }
        microphone.onFailure = { [weak self] message in
            guard let self, self.isCapturingChinese else { return }
            self.fail(message)
        }
        speech.onPlaybackStarted = { [weak self] in
            guard let self, self.phase == .synthesizing else { return }
            self.phase = .speaking
            self.status = "正在播放外语译文。“听朋友”已暂停，播放结束后自动继续。"
        }
        speech.onFinished = { [weak self] in
            guard let self, self.phase == .speaking else { return }
            self.draft.markSent()
            self.continueAfterPlayback()
        }
        speech.onFailure = { [weak self] message in
            guard let self, self.phase == .synthesizing || self.phase == .speaking else { return }
            self.fail(message)
        }
        _ = refreshDevices()
    }

    func selectProvider(_ value: TranslationProvider) {
        guard value != provider else { return }
        stop()
        incoming.clearCaptions()
        provider = value
        status = "已选择\(value.title)，听朋友和中文回复均使用此服务翻译。"
    }

    var recognitionTitle: String {
        language?.localeLanguage.languageCode?.identifier == "en" && localEnglishRecognition
            ? "Parakeet 本地英文" : (allowNetworkRecognition ? "Apple 语音识别 · 允许联网" : "Apple 本地语音识别")
    }

    func editChinese(_ text: String) {
        guard !isBusy else { return }
        draft.edit(text)
        failure = nil
    }

    func refreshLanguages() async {
        guard !isRefreshingLanguages, !isBusy, !isHearingFriend else { return }
        isRefreshingLanguages = true
        defer { isRefreshingLanguages = false }
        let installed = await listLanguages()
        guard !Task.isCancelled, !isBusy, !isHearingFriend else { return }
        availableLanguages = installed
        if let language, installed.contains(language) {
            refreshVoices()
            return
        }
        selectLanguage(installed.first)
    }

    func selectLanguage(_ selected: TargetLanguage?) {
        if let selected, !availableLanguages.contains(selected) { return }
        guard selected != language else { return }
        stop()
        incoming.clearCaptions()
        language = selected
        refreshVoices()
        status = selected.map { "已切换到\($0.title)，可听朋友或重新翻译中文后播放。" }
            ?? "未检测到已安装的中外文翻译语言包，请下载后刷新语言列表。"
    }

    func refreshVoices() {
        guard let language else {
            availableVoices = []
            selectedVoiceID = nil
            return
        }
        availableVoices = SpeechVoice.matching(listVoices(), language: language)
        let saved = voicePreferences.dictionary(forKey: "speechVoiceByLanguage")?[language.id] as? String
        selectedVoiceID = availableVoices.first { $0.id == saved }?.id
    }

    func selectVoice(_ id: String?) {
        guard !isBusy, let language else { return }
        if let id, !availableVoices.contains(where: { $0.id == id }) { return }
        selectedVoiceID = id
        var saved = voicePreferences.dictionary(forKey: "speechVoiceByLanguage") as? [String: String] ?? [:]
        saved[language.id] = id
        voicePreferences.set(saved, forKey: "speechVoiceByLanguage")
    }

    private func refreshDevices() -> Bool {
        do {
            devices = try listDevices()
            if !microphones.contains(where: { $0.id == microphoneID }) {
                microphoneID = microphones.first?.id ?? 0
            }
            if !monitors.contains(where: { $0.id == monitorID }) {
                monitorID = monitors.first?.id ?? 0
            }
            return true
        } catch {
            fail(error.localizedDescription)
            return false
        }
    }

    func startIncoming() {
        guard !isBusy, !isHearingFriend else { return }
        guard let language else { fail("请先下载翻译语言包并选择朋友的语言。"); return }
        guard refreshDevices() else { return }
        guard let device = selectedMicrophone else {
            fail("未找到电脑内建麦克风，暂时无法识别语音。"); return
        }
        failure = nil
        status = "正在听朋友；轮到你时点“我来说”。"
        incoming.start(
            device: device, language: language, allowNetwork: allowNetworkRecognition,
            preserveCaptions: true, provider: provider, model: deepSeekModel, ai: ai
        )
    }

    func startRecording() {
        guard !isBusy else { return }
        guard language != nil else { fail("请先下载翻译语言包并选择朋友的语言。"); return }
        guard refreshDevices() else { return }
        guard let device = selectedMicrophone else {
            fail("未找到电脑内建麦克风，请检查设备后重试。"); return
        }
        incoming.pauseForReply()
        turnID = UUID()
        draft.edit("")
        draft.invalidate()
        failure = nil
        phase = .authorizing
        status = "正在准备中文语音识别…"
        startupTimeout?.cancel()
        startupTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, self.phase == .authorizing else { return }
            self.startup?.cancel()
            self.fail("中文识别启动超时（\(self.status)）。已停止本次启动，请重试。")
        }
        startup = Task {
            do {
                try await microphone.start(device: device, allowNetwork: allowNetworkRecognition)
                guard !Task.isCancelled, phase == .authorizing else { return }
                startupTimeout?.cancel()
                startupTimeout = nil
                phase = .listening
                status = "正在听中文。说完后点击“说完了”；每句最长约 50 秒。"
            } catch is CancellationError {
                // 停止或切换语言主动取消权限等待，不覆盖新状态。
            } catch {
                guard !Task.isCancelled else { return }
                fail(error.localizedDescription)
            }
        }
    }

    func finishRecording() {
        guard phase == .listening else { return }
        phase = .finalizing
        status = "正在确认最后几个字…"
        microphone.finish()
    }

    func translate() {
        guard !isBusy else { return }
        guard let language else { fail("请先下载翻译语言包并选择朋友的语言。"); return }
        let text = draft.chinese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { fail("没有识别到中文，也可以直接输入文字。"); return }
        guard text.count <= 1000 else { fail("单句请控制在 1000 字以内，长内容请分段。"); return }
        incoming.pauseForReply()
        draft.invalidate()
        failure = nil
        pendingTranslation = TranslationWork(generation: draft.generation, text: text, language: language, provider: provider)
        phase = .translating
        status = "正在使用\(provider.title)翻译为\(language.title)…"
        if provider != .apple {
            translationConfiguration = nil
            let selected = provider
            let model = deepSeekModel
            let context = incoming.captions.rows.suffix(3).map { "朋友：\($0.original)" }
            cloudTask = Task {
                await runTranslation(language: language) { [ai] text, language in
                    try await ai.translate(TranslationInput(text: text, source: "zh-Hans", target: language.id, context: context), provider: selected, model: model)
                }
            }
            return
        }
        if translationConfiguration != nil {
            translationConfiguration?.invalidate()
        } else {
            translationConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "zh-Hans"),
                target: language.localeLanguage
            )
        }
    }

    func runTranslation(_ session: TranslationSession, language expectedLanguage: TargetLanguage?) async {
        guard let expectedLanguage, provider == .apple else { return }
        await runTranslation(language: expectedLanguage) { text, language in
            let availability = await LanguageAvailability().status(
                from: Locale.Language(identifier: "zh-Hans"),
                to: language.localeLanguage
            )
            try Task.checkCancellation()
            guard availability != .unsupported else {
                throw InterpreterError("此 macOS 的 Apple 翻译尚不支持中文到\(language.title)。请检查系统版本和语言支持。")
            }
            try await session.prepareTranslation()
            try Task.checkCancellation()
            return try await session.translate(text).targetText
        }
    }

    func runTranslation(
        language expectedLanguage: TargetLanguage,
        using translate: (String, TargetLanguage) async throws -> String
    ) async {
        guard let work = pendingTranslation, work.language == expectedLanguage else { return }
        do {
            let translatedText = try await translate(work.text, work.language)
            guard isCurrent(work) else { return }
            guard draft.commit(translatedText, generation: work.generation) else {
                throw InterpreterError("系统返回了空译文，请重试。")
            }
            phase = .idle
            pendingTranslation = nil
            playTranslation()
        } catch {
            guard isCurrent(work) else { return }
            pendingTranslation = nil
            fail("翻译未完成：\(error.localizedDescription)")
        }
    }

    func playTranslation() {
        guard !isBusy, draft.canPlay else { return }
        guard refreshDevices() else { return }
        guard let device = selectedSpeaker else {
            fail("未找到电脑内建扬声器，暂时无法播放译文。"); return
        }
        do { try play(on: device) } catch { fail(error.localizedDescription) }
    }

    func stop() {
        cloudTask?.cancel()
        cloudTask = nil
        turnID = UUID()
        resumeListening?.cancel()
        resumeListening = nil
        incoming.stop()
        startupTimeout?.cancel()
        startupTimeout = nil
        startup?.cancel()
        startup = nil
        microphone.cancel()
        speech.stop()
        pendingTranslation = nil
        translationConfiguration = nil
        draft.invalidate()
        phase = .idle
        failure = nil
        status = "已停止收听和播报。点“听朋友”或“我来说”重新开始。"
    }

    private func play(on device: AudioDevice) throws {
        guard let language else { throw InterpreterError("请先选择朋友的语言。") }
        incoming.pauseForReply()
        failure = nil
        phase = .synthesizing
        status = "正在合成\(language.title)语音…"
        try speech.speak(draft.translation, language: language, voiceID: selectedVoiceID, device: device)
    }

    private func isCurrent(_ work: TranslationWork) -> Bool {
        !Task.isCancelled && phase == .translating && work.generation == draft.generation
            && work.language == language && work.provider == provider
    }

    private func continueAfterPlayback() {
        phase = .returningToFriend
        status = "播放完成，正在恢复听朋友…"
        let token = turnID
        resumeListening?.cancel()
        resumeListening = Task { [weak self] in
            guard let cooldown = self?.playbackCooldown else { return }
            // 留出短暂余音时间，避免把句尾播报收成朋友原文。
            try? await Task.sleep(for: cooldown)
            guard !Task.isCancelled, let self, self.turnID == token,
                  self.phase == .returningToFriend else { return }
            self.resumeListening = nil
            self.phase = .idle
            self.startIncoming()
        }
    }

    private func fail(_ message: String) {
        cloudTask?.cancel()
        cloudTask = nil
        turnID = UUID()
        resumeListening?.cancel()
        resumeListening = nil
        startup?.cancel()
        startup = nil
        startupTimeout?.cancel()
        startupTimeout = nil
        microphone.cancel()
        speech.stop()
        pendingTranslation = nil
        phase = .idle
        failure = message
        status = "请处理提示后重试，当前文字已保留。"
    }
}
