import SwiftUI
import AVFoundation
@preconcurrency import Translation

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let translationLanguage = model.language
        VStack(spacing: 0) {
            header
            languageControls
            GeometryReader { geometry in
                ScrollView {
                    let layout = geometry.size.width >= 960
                        ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
                        : AnyLayout(VStackLayout(spacing: 20))
                    layout {
                        IncomingView(incoming: model.incoming, language: model.language)
                        conversation
                    }
                    .padding(24)
                    .frame(maxWidth: 1440)
                    .frame(maxWidth: .infinity)
                }
            }
            controls
        }
        .frame(minWidth: 800, minHeight: 680)
        .background(InterpreterStyle.canvas)
        .tint(InterpreterStyle.accent)
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

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 23))
                .foregroundStyle(InterpreterStyle.accent)
                .frame(width: 48, height: 48)
                .background(InterpreterStyle.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("朋友之间语言翻译器")
                    .font(.system(size: 23, weight: .semibold))
                Text("听取说话内容，显示原文和翻译。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            InterpreterStatus(title: "语音听译", symbol: "waveform")
            SettingsLink {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .help("语音识别与翻译服务设置")
            .accessibilityLabel("打开设置")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var languageControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("朋友的语言", systemImage: "globe")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Picker("朋友的语言", selection: Binding(get: { model.language }, set: { model.selectLanguage($0) })) {
                            if model.language == nil {
                                Text(model.isRefreshingLanguages ? "正在读取…" : "暂无已下载语言")
                                    .tag(Optional<TargetLanguage>.none)
                            }
                            ForEach(model.availableLanguages) { Text($0.title).tag(Optional($0)) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .disabled(model.availableLanguages.isEmpty)
                        Button {
                            Task { await model.refreshLanguages() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("刷新系统已下载的翻译语言")
                        .accessibilityLabel("刷新翻译语言和音色")
                        .disabled(model.isRefreshingLanguages || model.isBusy || model.isHearingFriend)
                    }
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    Label("翻译服务", systemImage: "text.bubble")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("翻译服务", selection: Binding(get: { model.provider }, set: { model.selectProvider($0) })) {
                        ForEach(TranslationProvider.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                .frame(width: 135)
                VStack(alignment: .leading, spacing: 8) {
                    Label("播报音色", systemImage: "speaker.wave.2")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Picker("播报音色", selection: Binding(get: { model.selectedVoiceID }, set: { model.selectVoice($0) })) {
                        Text(model.availableVoices.isEmpty ? "未找到可用音色" : "自动选择")
                            .tag(Optional<String>.none)
                        ForEach(model.availableVoices) { Text($0.title).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .disabled(model.isBusy || model.availableVoices.isEmpty)
                    .help("系统朗读音色，按语言记住选择；自动选择不等于跟随系统设置的声音")
                }.frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            if model.availableLanguages.isEmpty {
                Label("下载中文和朋友语言的翻译包后，点击刷新。朗读音色需单独下载。", systemImage: "arrow.down.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(InterpreterStyle.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(InterpreterStyle.border, lineWidth: 1)
        }
        .padding(.horizontal, 24)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let failure = model.failure {
                InterpreterNotice(message: failure)
            }
            HStack(spacing: 10) {
                if model.isBusy || model.incoming.isStarting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: model.isHearingFriend ? "waveform" : "circle.dashed")
                        .foregroundStyle(model.isHearingFriend ? InterpreterStyle.listening : .secondary)
                        .accessibilityHidden(true)
                }
                Text(model.displayStatus)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button(action: model.startIncoming) {
                    Label(model.isHearingFriend ? "正在听朋友" : "听朋友", systemImage: "ear.fill")
                        .frame(minWidth: 110, minHeight: 24)
                }
                .buttonStyle(.bordered)
                .tint(InterpreterStyle.listening)
                .disabled(model.isBusy || model.isHearingFriend || model.language == nil)
                if model.phase == .listening {
                    Button(action: model.finishRecording) {
                        Label("说完了", systemImage: "checkmark.circle.fill")
                            .frame(minWidth: 110, minHeight: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                } else {
                    Button(action: model.startRecording) {
                        Label("我来说", systemImage: "mic.fill")
                            .frame(minWidth: 110, minHeight: 24)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isBusy || model.language == nil)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                Text("⌘ ↵ 说话 / 完成")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(role: .destructive, action: model.stop) {
                    Label("停止", systemImage: "stop.fill")
                        .frame(minHeight: 24)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])
                .help("停止全部收听与播报（Esc）")
            }
            .controlSize(.large)
            HStack(spacing: 6) {
                Text(model.recognitionTitle)
                Image(systemName: "arrow.right").accessibilityHidden(true)
                Text(model.provider == .apple ? "Apple 离线翻译" : "\(model.provider.title) · 上下文翻译")
                Spacer(minLength: 0)
                Text("内建麦克风 / 扬声器")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(InterpreterStyle.surface)
        .overlay(alignment: .top) { Divider() }
    }

    private var conversation: some View {
        InterpreterCard {
            VStack(alignment: .leading, spacing: 16) {
                InterpreterSectionHeading(
                    title: "我来说", subtitle: "说中文，播放外语给朋友听",
                    symbol: "mic.fill", color: InterpreterStyle.accent
                )
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("我的中文").font(.callout.weight(.semibold))
                        Spacer()
                        Text("可直接输入或修改").font(.caption).foregroundStyle(.secondary)
                    }
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: Binding(get: { model.draft.chinese }, set: { model.editChinese($0) }))
                            .font(.system(size: 18))
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .disabled(model.isBusy)
                            .accessibilityLabel("我的中文")
                            .accessibilityHint("输入或修改后，点击翻译并播放")
                        if model.draft.chinese.isEmpty {
                            Text(model.isCapturingChinese ? "正在听你说中文…" : "点击“我来说”，或在这里输入中文…")
                                .font(.system(size: 18)).foregroundStyle(.secondary)
                                .padding(.horizontal, 15).padding(.vertical, 18)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(height: 130)
                    .background(InterpreterStyle.inset, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(InterpreterStyle.border, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("外语译文", systemImage: "speaker.wave.2")
                            .font(.callout.weight(.semibold))
                        Spacer()
                        Text("\(model.language?.title ?? "尚未选择语言") · \(model.provider.title)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ScrollView {
                        Text(model.draft.translation.isEmpty ? "翻译完成后，外语译文会在这里显示并自动播放。" : model.draft.translation)
                            .font(.system(size: 18))
                            .foregroundStyle(model.draft.translation.isEmpty ? .secondary : .primary)
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .textSelection(.enabled).padding(14)
                    }
                    .frame(height: 116)
                    .background(InterpreterStyle.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                HStack(spacing: 10) {
                    Button(action: model.translate) {
                        Label("翻译并播放", systemImage: "play.fill")
                    }
                    .disabled(model.isBusy || model.language == nil || model.draft.chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer(minLength: 0)
                    Button(action: model.playTranslation) {
                        Label(model.draft.sent ? "再次播放" : "播放译文", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isBusy || !model.draft.canPlay)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Label("播放时暂停收听，结束后自动继续听朋友。", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
