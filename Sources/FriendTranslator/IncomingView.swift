import SwiftUI
@preconcurrency import Translation

struct IncomingView: View {
    @Bindable var incoming: IncomingModel
    let language: TargetLanguage?
    var provider: TranslationProvider = .apple
    var panelHeight: CGFloat = 460
    var canEdit = true
    var audioSource: FriendAudioSource = .microphone
    let onSelectAudioSource: (FriendAudioSource) -> Void
    let onRetranslate: (UUID, String) -> Void
    @State private var editedOriginals: [UUID: String] = [:]
    @FocusState private var focusedCaption: UUID?

    var body: some View {
        let host = incoming.hostID
        InterpreterCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    InterpreterSectionHeading(
                        title: "对方说的话", subtitle: language?.title ?? "未选择语言",
                        symbol: "captions.bubble", color: InterpreterStyle.listening
                    )
                    Spacer(minLength: 0)
                    Button("清空", role: .destructive) {
                        incoming.clearDisplayedCaptions()
                        editedOriginals.removeAll()
                        focusedCaption = nil
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canEdit || (incoming.captions.rows.isEmpty && incoming.failure == nil))
                    .help("清空对方的原文与译文，并暂停收听")
                    .accessibilityLabel("清空对方说的话")
                }
                .help("翻译服务：\(provider.title)")
                sourceSelection
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        if !incoming.captions.rows.isEmpty {
                            LazyVStack(alignment: .leading, spacing: 20) {
                                if incoming.isStarting {
                                    Text(incoming.status)
                                        .font(InterpreterStyle.callout).foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                ForEach(incoming.captions.rows) { row in
                                    VStack(alignment: .leading, spacing: 10) {
                                        originalEditor(row)
                                        Text(editedOriginals[row.id].map { $0 != row.original } == true
                                             ? "原文已修改，请点击“重新翻译”"
                                             : row.chinese.isEmpty ? (row.translationError != nil ? "翻译失败" : (incoming.isActive || incoming.isTranslatingManualText ? "正在翻译…" : "等待继续翻译")) : row.chinese)
                                            .font(InterpreterStyle.font(size: 21, weight: .medium))
                                            .foregroundStyle(row.chinese.isEmpty ? .secondary : .primary)
                                            .lineSpacing(6)
                                        if let error = row.translationError {
                                            Label(error, systemImage: "exclamationmark.triangle")
                                                .font(InterpreterStyle.caption).foregroundStyle(.secondary)
                                        } else if row.translatedRevision < row.revision, !row.chinese.isEmpty {
                                            Text("正在更新译文…")
                                                .font(InterpreterStyle.caption).foregroundStyle(.secondary)
                                        }
                                        Divider().padding(.top, 10)
                                    }
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 4)
                                    .id(row.id)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        if incoming.captions.rows.isEmpty { emptyState }
                    }
                    .onChange(of: incoming.captions.rows) {
                        let retained = Set(incoming.captions.rows.map(\.id))
                        editedOriginals = editedOriginals.filter { retained.contains($0.key) }
                        if let focusedCaption, !retained.contains(focusedCaption) { self.focusedCaption = nil }
                        if focusedCaption == nil, let id = incoming.captions.rows.last?.id {
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                }
                if let failure = incoming.failure {
                    InterpreterNotice(message: failure)
                }
            }
            .frame(height: panelHeight - 40, alignment: .top)
        }
        .onChange(of: focusedCaption) {
            if focusedCaption != nil, canEdit { incoming.pause() }
        }
        .background {
            Color.clear.frame(width: 0, height: 0)
                .translationTask(incoming.configuration) { session in
                    await incoming.runTranslation(session, host: host)
                }
                .id(host)
        }
    }

    private var sourceSelection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(FriendAudioSource.allCases) { source in
                    Button { onSelectAudioSource(source) } label: {
                        Label(source == .microphone ? "面对面" : "Telegram 通话",
                              systemImage: source == .microphone ? "person.2" : "phone")
                            .font(InterpreterStyle.callout)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(audioSource == source ? InterpreterStyle.accent : .secondary)
                            .background(audioSource == source ? InterpreterStyle.surface : .clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canEdit)
                    .accessibilityAddTraits(audioSource == source ? .isSelected : [])
                }
            }
            .padding(4)
            .background(InterpreterStyle.inset, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("通话模式")
            HStack(alignment: .top, spacing: 8) {
                Text(audioSource == .microphone ? "通过麦克风听朋友说话" : "戴耳机听 Telegram；中文回复可翻译并发送到通话")
                    .font(InterpreterStyle.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                listeningStatus
            }
        }
    }

    private func originalEditor(_ row: IncomingCaption) -> some View {
        let original = editedOriginals[row.id] ?? row.original
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(trimmed.count > 4000 ? "原文最多 4000 字" : "原文 · 可直接编辑")
                    .font(InterpreterStyle.caption).foregroundStyle(.secondary)
                Spacer()
                Button("重新翻译") {
                    onRetranslate(row.id, original)
                    editedOriginals.removeValue(forKey: row.id)
                    focusedCaption = nil
                }
                .disabled(!canEdit || incoming.isTranslatingManualText || trimmed.isEmpty || trimmed.count > 4000)
                .help("用修改后的原文更新这条中文字幕")
            }
            TextField("输入对方说的原文", text: Binding(
                get: { editedOriginals[row.id] ?? row.original },
                set: { text in
                    if incoming.isActive || incoming.isStarting || incoming.isTranslatingManualText { incoming.pause() }
                    editedOriginals[row.id] = text
                }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(InterpreterStyle.font(size: 15))
            .foregroundStyle(.secondary)
            .lineSpacing(3)
            .lineLimit(1...12)
            .focused($focusedCaption, equals: row.id)
            .disabled(!canEdit)
            .accessibilityLabel("对方说的原文，可编辑")
        }
    }

    @ViewBuilder
    private var listeningStatus: some View {
        if incoming.failure != nil {
            InterpreterStatus(title: "需重试", symbol: "exclamationmark.circle")
        } else if incoming.isTranslatingManualText {
            InterpreterStatus(title: "手动翻译中", symbol: "text.bubble", color: InterpreterStyle.listening)
        } else if incoming.isPaused {
            InterpreterStatus(title: "已暂停", symbol: "pause.circle")
        } else if incoming.isStarting {
            InterpreterStatus(title: "准备中", symbol: "ellipsis.circle", color: InterpreterStyle.listening)
        } else if incoming.isActive {
            InterpreterStatus(title: "收听中", symbol: "waveform", color: InterpreterStyle.listening)
        } else if !incoming.captions.rows.isEmpty {
            InterpreterStatus(title: "已停止", symbol: "stop.circle")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(InterpreterStyle.font(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(incoming.isStarting ? "正在准备收听" : incoming.isActive ? "等待对方说话" : "暂无字幕")
                .font(InterpreterStyle.font(size: 16, weight: .medium))
            Text(incoming.isStarting ? incoming.status : incoming.isActive ? "识别到的内容将实时显示" : "点击“听朋友”开始收听，或在底部手动输入原文")
                .font(InterpreterStyle.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }
}
