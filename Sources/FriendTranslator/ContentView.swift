import SwiftUI
import AVFoundation
@preconcurrency import Translation

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingVoiceOptions = false
    @State private var showingTelegramConnection = false
    @State private var manualFriendText = ""

    var body: some View {
        let translationLanguage = model.language
        VStack(spacing: 0) {
            toolbar
            Divider()
            if model.availableLanguages.isEmpty {
                languageNotice
            }
            GeometryReader { geometry in
                let panelHeight = max(440, geometry.size.height - InterpreterStyle.pageInset * 2)
                ScrollView {
                    HStack(alignment: .top, spacing: 16) {
                        IncomingView(
                            incoming: model.incoming, language: model.language,
                            provider: model.incoming.provider, panelHeight: panelHeight,
                            canEdit: !model.isBusy,
                            audioSource: model.friendAudioSource,
                            onSelectAudioSource: model.selectFriendAudioSource,
                            onRetranslate: { id, text in model.translateFriendText(text, replacing: id) }
                        )
                        conversation(panelHeight: panelHeight)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(InterpreterStyle.pageInset)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            Divider()
            manualFriendInput
        }
        .frame(minWidth: 800, minHeight: 680)
        .background(InterpreterStyle.canvas)
        .font(InterpreterStyle.body)
        .tint(InterpreterStyle.accent)
        .onExitCommand { model.stop() }
        .task(id: scenePhase) {
            if scenePhase == .active { await model.refreshLanguages() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            model.refreshVoices()
        }
        .translationTask(model.translationConfiguration) { session in
            await model.runTranslation(session, language: translationLanguage)
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) {
                    controls.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    translationOptions
                }
                VStack(alignment: .leading, spacing: 12) {
                    controls.fixedSize(horizontal: true, vertical: false)
                    translationOptions.frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            if let failure = model.failure {
                InterpreterNotice(message: failure)
            }
        }
        .controlSize(.regular)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, InterpreterStyle.pageInset)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(InterpreterStyle.surface)
    }

    private var translationOptions: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("中文").font(InterpreterStyle.callout.weight(.medium))
                Image(systemName: "arrow.left.arrow.right")
                    .font(InterpreterStyle.caption).foregroundStyle(.secondary)
                    .accessibilityLabel("双向翻译")
                InterpreterMenu(title: model.language?.title ?? "选择语言") {
                    ForEach(model.availableLanguages) { language in
                        InterpreterMenuOption(title: language.title, selected: model.language == language) {
                            model.selectLanguage(language)
                        }
                    }
                }
                .frame(width: 220)
                .accessibilityLabel("对方语言")
                .disabled(model.availableLanguages.isEmpty)
                .help("对方语言；切换后会结束当前收听并清空字幕")
            }
            Divider().frame(height: 24)
            InterpreterMenu(title: model.provider.title) {
                ForEach(TranslationProvider.allCases) { provider in
                    InterpreterMenuOption(title: provider.title, selected: model.provider == provider) {
                        model.selectProvider(provider)
                    }
                }
            }
            .frame(width: 165)
            .accessibilityLabel("翻译服务")
            .help("翻译服务；切换后会结束当前收听并清空字幕")
            Button {
                if !showingVoiceOptions { model.refreshDevices() }
                showingVoiceOptions.toggle()
            } label: {
                Image(systemName: "speaker.wave.2")
                    .frame(width: 32, height: 36)
            }
            .accessibilityLabel("播报音色")
            .help("播报音色")
            .popover(isPresented: $showingVoiceOptions, arrowEdge: .bottom) {
                voiceOptions
            }
            SettingsLink {
                Image(systemName: "gearshape")
                    .frame(width: 32, height: 36)
            }
            .help("设置")
            .accessibilityLabel("打开设置")
        }
        .buttonStyle(.borderless)
    }

    private var voiceOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("播报音色").font(InterpreterStyle.headline)
            InterpreterMenu(title: model.availableVoices.first { $0.id == model.selectedVoiceID }?.title ?? "自动选择") {
                InterpreterMenuOption(title: "自动选择", selected: model.selectedVoiceID == nil) {
                    model.selectVoice(nil)
                }
                ForEach(model.availableVoices) { voice in
                    InterpreterMenuOption(title: voice.title, selected: model.selectedVoiceID == voice.id) {
                        model.selectVoice(voice.id)
                    }
                }
            }
            .accessibilityLabel("播报音色")
            .disabled(model.isBusy || model.availableVoices.isEmpty)
            Text("本机播放设备").font(InterpreterStyle.caption).foregroundStyle(.secondary)
            InterpreterMenu(title: model.selectedSpeaker?.name ?? "选择播放设备") {
                ForEach(model.monitors) { device in
                    InterpreterMenuOption(title: device.name, selected: model.monitorID == device.id) {
                        model.monitorID = device.id
                    }
                }
            }
            .accessibilityLabel("本机播放设备")
            .disabled(model.isBusy || model.monitors.isEmpty)
            Text(model.isBusy ? "播报或录音结束后可更换音色。" : "按语言保存选择。可在系统设置中下载更多声音。")
                .font(InterpreterStyle.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Button {
                Task { await model.refreshLanguages() }
            } label: {
                Label(model.isRefreshingLanguages ? "正在刷新…" : "刷新语言与音色", systemImage: "arrow.clockwise")
            }
            .disabled(model.isRefreshingLanguages || model.isBusy || model.isHearingFriend)
            .help("停止收听与播报后可刷新资源")
        }
        .padding(20)
        .frame(width: 510)
    }

    private var languageNotice: some View {
        HStack(spacing: 12) {
            if model.isRefreshingLanguages {
                ProgressView().controlSize(.small)
                Text("正在读取已下载语言…")
            } else {
                Label("请先下载中文和对方语言的翻译包。", systemImage: "arrow.down.circle")
                Spacer()
                Button("刷新语言") { Task { await model.refreshLanguages() } }
                    .disabled(model.isBusy || model.isHearingFriend)
            }
        }
        .font(InterpreterStyle.callout)
        .padding(14)
        .background(InterpreterStyle.surface, in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, InterpreterStyle.pageInset).padding(.top, 12)
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                if isProcessing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: model.isHearingFriend || model.phase == .listening ? "waveform" : "circle.fill")
                        .font(InterpreterStyle.font(size: model.isHearingFriend || model.phase == .listening ? 16 : 6))
                        .foregroundStyle(model.isHearingFriend || model.phase == .listening ? InterpreterStyle.accent : .secondary)
                        .accessibilityHidden(true)
                }
                Text(activityTitle).font(InterpreterStyle.callout)
                    .lineLimit(1)
            }
            .help(model.displayStatus)
            Spacer(minLength: 16)
            Button(action: model.toggleIncoming) {
                Label(model.isHearingFriend ? "暂停收听" : "听朋友", systemImage: model.isHearingFriend ? "pause.fill" : "ear")
                    .frame(minWidth: 96, minHeight: 34)
            }
            .buttonStyle(.bordered)
            .disabled(model.isBusy || model.language == nil)
            .help(model.isHearingFriend ? "暂停收听，保留当前字幕" : "开始或继续听朋友")
            Button {
                if model.phase == .listening { model.finishRecording() } else { model.startRecording() }
            } label: {
                Label(model.phase == .listening ? "说完了" : "我来说", systemImage: model.phase == .listening ? "checkmark" : "mic.fill")
                    .frame(minWidth: 96, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .disabled((model.isBusy && model.phase != .listening) || model.language == nil)
            .keyboardShortcut(.return, modifiers: .command)
            .help("开始或完成中文录音（⌘ Return）")
        }
    }

    private var manualFriendInput: some View {
        let heading = Label("手动输入朋友说的话", systemImage: "keyboard")
            .font(InterpreterStyle.callout.weight(.semibold))
            .fixedSize()
        let direction = Text("\(model.language?.title ?? "对方语言") → 中文")
            .font(InterpreterStyle.caption).foregroundStyle(.secondary)
            .lineLimit(1)
        return VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    heading
                    manualProviderPicker
                    Spacer()
                    direction
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack { heading; Spacer(); direction }
                    manualProviderPicker
                }
            }
            HStack(alignment: .bottom, spacing: 12) {
                TextField("输入或粘贴朋友说的外语原文", text: $manualFriendText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2...4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(InterpreterStyle.inset, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(InterpreterStyle.border) }
                    .accessibilityLabel("朋友说的原文，手动输入")
                if model.incoming.isTranslatingManualText {
                    ProgressView().controlSize(.small)
                    Button("取消翻译", action: model.stop)
                }
                Button("翻译成中文") { model.translateFriendText(manualFriendText) }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || model.language == nil || model.incoming.isTranslatingManualText
                              || manualFriendText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || manualFriendText.trimmingCharacters(in: .whitespacesAndNewlines).count > 4000)
            }
            Text(manualFriendText.trimmingCharacters(in: .whitespacesAndNewlines).count > 4000
                 ? "原文最多 4000 字，请缩短后再翻译。"
                 : "手动翻译会暂停收听，结果显示在上方“对方说的话”中。输入内容会保留，方便修改。")
                .font(InterpreterStyle.caption).foregroundStyle(.secondary)
        }
        .controlSize(.regular)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, InterpreterStyle.pageInset)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(InterpreterStyle.surface)
    }

    private var manualProviderPicker: some View {
        HStack(spacing: 2) {
            ForEach([TranslationProvider.deepSeek, .apple]) { provider in
                Button {
                    model.manualTranslationProvider = provider
                } label: {
                    Text(provider.title)
                        .font(InterpreterStyle.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(model.manualTranslationProvider == provider
                                    ? InterpreterStyle.surface : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.manualTranslationProvider == provider ? .isSelected : [])
            }
        }
        .padding(3)
        .background(InterpreterStyle.inset, in: RoundedRectangle(cornerRadius: 8))
        .frame(width: 330)
        .accessibilityLabel("手动翻译服务")
        .disabled(model.isBusy || model.incoming.isTranslatingManualText)
        .help("用于手动输入和修改原文后的重新翻译，不改变实时收听的翻译服务")
    }

    private var isProcessing: Bool {
        model.incoming.isStarting || model.incoming.isTranslatingManualText || (model.isBusy && model.phase != .listening && model.phase != .speaking)
    }

    private var activityTitle: String {
        if model.failure != nil || model.incoming.failure != nil { return "需要重试" }
        switch model.phase {
        case .idle:
            if model.incoming.isTranslatingManualText { return "正在翻译手动输入…" }
            if model.incoming.isStarting { return "正在准备收听…" }
            if model.incoming.isActive { return "正在收听对方" }
            if model.incoming.isPaused { return "收听已暂停" }
            return model.language == nil ? "请先选择语言" : "就绪"
        case .authorizing: return "正在准备录音…"
        case .listening: return "正在听你说话"
        case .finalizing: return "正在整理语音…"
        case .translating: return "正在翻译…"
        case .synthesizing: return "正在生成语音…"
        case .speaking: return model.isSendingToTelegram ? "正在发送到 Telegram" : "正在播放译文"
        case .returningToFriend: return "正在恢复收听…"
        }
    }

    private var telegramConnectionHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("把译文送给 Telegram 好友").font(InterpreterStyle.headline)
            Text("在 Telegram 通话设置中，把麦克风选为 BlackHole 2ch，扬声器选为耳机，并保持通话麦克风开启。")
            Text("点“说完了”后会翻译并发送；“试听”仅在本机播放。")
            Divider()
            Text(model.telegramConnectionStatus).foregroundStyle(.secondary)
            Button("检查连接", action: model.checkTelegramConnection).disabled(model.isBusy)
        }
        .font(InterpreterStyle.callout)
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: 380)
    }

    private func conversation(panelHeight: CGFloat) -> some View {
        let textHeight = max(120, (panelHeight - 280) * 0.4)
        return InterpreterCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    InterpreterSectionHeading(
                        title: "我的回复", subtitle: "中文",
                        symbol: "mic", color: InterpreterStyle.accent
                    )
                    if model.friendAudioSource == .telegram {
                        Spacer(minLength: 0)
                        Button("通话连接") { showingTelegramConnection = true }
                            .buttonStyle(.borderless)
                            .popover(isPresented: $showingTelegramConnection) { telegramConnectionHelp }
                    }
                }
                Divider()
                ZStack(alignment: .topLeading) {
                    TextEditor(text: Binding(get: { model.draft.chinese }, set: { model.editChinese($0) }))
                        .font(InterpreterStyle.font(size: 18))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .disabled(model.isBusy)
                        .accessibilityLabel("我的中文")
                        .accessibilityHint(model.friendAudioSource == .telegram ? "输入或修改后，点击翻译并发送" : "输入或修改后，点击翻译并播放")
                    if model.draft.chinese.isEmpty {
                        Text(model.isCapturingChinese ? "正在听你说话…" : "输入中文，或点击“我来说”")
                            .font(InterpreterStyle.font(size: 18)).foregroundStyle(.secondary)
                            .padding(.horizontal, 15).padding(.vertical, 18)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .frame(height: textHeight)
                .background(InterpreterStyle.inset, in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(InterpreterStyle.border, lineWidth: 1)
                        .allowsHitTesting(false)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("译文").font(InterpreterStyle.callout.weight(.medium))
                        Spacer()
                        Text(model.language?.title ?? "未选择语言")
                            .font(InterpreterStyle.caption).foregroundStyle(.secondary)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.draft.translation, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!model.draft.canPlay)
                        .accessibilityLabel("复制译文")
                        .help("复制后可粘贴到 Telegram，让好友看到译文")
                    }
                    ScrollView {
                        Text(model.draft.translation.isEmpty ? "等待翻译" : model.draft.translation)
                            .font(InterpreterStyle.font(size: 20, weight: .medium))
                            .foregroundStyle(model.draft.translation.isEmpty ? .secondary : .primary)
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled).padding(14)
                    }
                    .frame(maxHeight: .infinity)
                    .background(InterpreterStyle.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 10) {
                    Text("语速 · \(model.speechRateTitle)")
                    Text("慢").foregroundStyle(.secondary)
                    Slider(
                        value: Binding(get: { model.speechRate }, set: { model.selectSpeechRate($0) }),
                        in: SpeechOutput.rateRange, step: 0.05
                    ) { Text("播报语速") }
                    .accessibilityValue(model.speechRateTitle)
                    .frame(maxWidth: 200)
                    Text("快").foregroundStyle(.secondary)
                    Button("恢复标准") { model.selectSpeechRate(SpeechOutput.defaultRate) }
                        .buttonStyle(.borderless)
                    Spacer(minLength: 0)
                }
                .font(InterpreterStyle.caption)
                .disabled(model.isBusy)
                .help("试听和发送译文共用此语速，调整后在下一次播放时生效，并自动保存。")
                HStack(spacing: 10) {
                    Button(action: model.playTranslation) {
                        Label(model.friendAudioSource == .telegram ? "试听" : (model.draft.sent ? "重播" : "播放译文"), systemImage: "speaker.wave.2")
                    }
                    .disabled(model.isBusy || !model.draft.canPlay)
                    if model.friendAudioSource == .telegram {
                        Button(action: model.sendTranslation) {
                            Label("发送译文", systemImage: "paperplane.fill")
                        }
                        .disabled(model.isBusy || !model.draft.canPlay)
                        .help("把当前译文播放到 Telegram 通话；不会重新翻译")
                    }
                    Spacer(minLength: 0)
                    Button(action: model.translate) {
                        Label(model.friendAudioSource == .telegram ? "翻译并发送" : "翻译并播放", systemImage: model.friendAudioSource == .telegram ? "paperplane.fill" : "play.fill")
                    }
                    .disabled(model.isBusy || model.language == nil || model.draft.chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .frame(height: panelHeight - 40)
        }
    }
}
