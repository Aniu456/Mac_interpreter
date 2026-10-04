import Foundation
import Observation
@preconcurrency import Translation

@MainActor
@Observable
final class IncomingModel {
    private(set) var captions = IncomingCaptions()
    private(set) var isActive = false
    private(set) var isStarting = false
    private(set) var isPaused = false
    private(set) var language: TargetLanguage?
    private(set) var status = "手机微信开免提，点“听朋友”后显示外语原文和中文。"
    private(set) var failure: String?
    private(set) var hostID = UUID()
    var configuration: TranslationSession.Configuration?
    private(set) var provider = TranslationProvider.apple
    @ObservationIgnored private var cloudTask: Task<Void, Never>?
    @ObservationIgnored private let recognizer: any IncomingRecognizing
    @ObservationIgnored private let startupDeadline: Duration
    @ObservationIgnored private var startup: Task<Void, Never>?
    @ObservationIgnored private var startupTimeout: Task<Void, Never>?
    @ObservationIgnored private var debounce: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var signals: AsyncStream<Void>?
    @ObservationIgnored private var continuation: AsyncStream<Void>.Continuation?
    @ObservationIgnored private var pending: [UUID: IncomingCaption] = [:]

    init(recognizer: any IncomingRecognizing = LanguageRecognizer(), startupDeadline: Duration = .seconds(180)) {
        self.recognizer = recognizer
        self.startupDeadline = startupDeadline
        recognizer.onText = { [weak self] id, text, final in self?.receive(id: id, text: text, final: final) }
        recognizer.onStatus = { [weak self] message in self?.status = message }
        recognizer.onFailure = { [weak self] message in
            self?.stop()
            self?.failure = message
        }
    }

    func start(device: AudioDevice, language: TargetLanguage, allowNetwork: Bool, preserveCaptions: Bool = false, provider: TranslationProvider = .apple, model: DeepSeekModel = .flash, ai: any AITranslating = AITranslator()) {
        guard !isActive, !isStarting else { return }
        stop()
        if !preserveCaptions { captions = IncomingCaptions() }
        self.language = language
        self.provider = provider
        failure = nil
        isStarting = true
        status = "正在准备听手机声音，请允许麦克风和语音识别。"
        let token = hostID
        let pair = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        signals = pair.stream
        continuation = pair.continuation
        startupTimeout = Task { [weak self] in
            guard let deadline = self?.startupDeadline else { return }
            try? await Task.sleep(for: deadline)
            guard !Task.isCancelled, let self, self.hostID == token, self.isStarting else { return }
            let stage = self.status
            self.stop()
            self.failure = "朋友字幕启动超时（\(stage)）。请处理权限提示后重新开启字幕。"
        }
        startup = Task {
            do {
                try await recognizer.start(device: device, language: language, allowNetwork: allowNetwork)
                guard !Task.isCancelled, hostID == token else { return }
                startupTimeout?.cancel()
                startupTimeout = nil
                isStarting = false
                isActive = true
                status = "正在听手机免提中朋友的声音…轮到你时点“我来说”。"
                if provider == .apple {
                    configuration = TranslationSession.Configuration(source: language.localeLanguage, target: Locale.Language(identifier: "zh-Hans"))
                } else {
                    cloudTask = Task {
                        await consumeTranslations(host: token) { input in
                            try await ai.translate(input, provider: provider, model: model)
                        }
                    }
                }
                // 暂停会取消未完成的翻译；恢复时继续处理保留的原文。
                for row in captions.rows { enqueue(row.id) }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, hostID == token else { return }
                stop()
                failure = error.localizedDescription
            }
        }
    }

    func stop() {
        cloudTask?.cancel()
        cloudTask = nil
        hostID = UUID()
        startupTimeout?.cancel()
        startupTimeout = nil
        startup?.cancel()
        startup = nil
        recognizer.stop()
        for task in debounce.values { task.cancel() }
        debounce.removeAll()
        continuation?.finish()
        continuation = nil
        signals = nil
        pending.removeAll()
        configuration = nil
        isActive = false
        isStarting = false
        isPaused = false
        status = "朋友字幕已停止，保留本次原文和中文。"
    }

    func pauseForReply() {
        guard !isPaused else { return }
        stop()
        isPaused = true
        status = "“听朋友”已暂停，电脑播报完成后自动继续。"
    }

    func clearCaptions() {
        captions = IncomingCaptions()
    }

    func runTranslation(_ session: TranslationSession, host expectedHost: UUID) async {
        guard expectedHost == hostID, provider == .apple, let language else { return }
        do {
            let availability = await LanguageAvailability().status(
                from: language.localeLanguage,
                to: Locale.Language(identifier: "zh-Hans")
            )
            guard expectedHost == hostID, !Task.isCancelled else { return }
            guard availability != .unsupported else { throw InterpreterError("系统尚不支持此语言到中文的翻译。") }
            try await session.prepareTranslation()
            await consumeTranslations(host: expectedHost) { input in
                try await session.translate(input.text).targetText
            }
        } catch {
            guard expectedHost == hostID, !Task.isCancelled else { return }
            // 原文识别可以继续，明确告知中文翻译不可用。
            failure = "中文翻译未就绪：\(error.localizedDescription)。原文仍会显示；处理语言资源后重新开启字幕。"
        }
    }

    func consumeTranslations(host expectedHost: UUID, using translate: (TranslationInput) async throws -> String) async {
        guard expectedHost == hostID, let signals, let language else { return }
        for await _ in signals {
            guard expectedHost == hostID, !Task.isCancelled else { return }
            while let work = captions.rows.first(where: { pending[$0.id] != nil }).flatMap({ pending.removeValue(forKey: $0.id) }) {
                // 只取当前段之前的原文；延迟返回的译文不反过来污染上下文。
                let context = captions.rows.prefix(while: { $0.id != work.id }).suffix(3).map(\.original)
                do {
                    let text = try await translate(TranslationInput(text: work.original, source: language.id, target: "zh-Hans", context: context))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard expectedHost == hostID, !Task.isCancelled else { return }
                    guard !text.isEmpty else { throw InterpreterError("翻译服务返回空译文。") }
                    captions.commit(id: work.id, revision: work.revision, chinese: text)
                } catch {
                    guard expectedHost == hostID, !Task.isCancelled else { return }
                    if captions.rows.first(where: { $0.id == work.id })?.revision == work.revision {
                        captions.fail(id: work.id, message: "\(provider.title) 翻译失败：\(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func receive(id: UUID, text: String, final: Bool) {
        guard isActive || isStarting else { return }
        captions.update(id: id, text: text)
        let retained = Set(captions.rows.map(\.id))
        pending = pending.filter { retained.contains($0.key) }
        if final {
            debounce.removeValue(forKey: id)?.cancel()
            enqueue(id)
        } else if debounce[id] == nil {
            let token = hostID
            debounce[id] = Task { [weak self] in
                try? await Task.sleep(for: self?.provider == .apple ? .milliseconds(700) : .milliseconds(1400))
                guard !Task.isCancelled, let self, self.hostID == token else { return }
                self.debounce.removeValue(forKey: id)
                self.enqueue(id)
            }
        }
    }

    private func enqueue(_ id: UUID) {
        guard let row = captions.rows.first(where: { $0.id == id }), row.revision > row.translatedRevision else { return }
        pending[id] = row
        continuation?.yield(())
    }
}
