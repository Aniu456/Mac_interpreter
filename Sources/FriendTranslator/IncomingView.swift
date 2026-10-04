import SwiftUI
@preconcurrency import Translation

struct IncomingView: View {
    @Bindable var incoming: IncomingModel
    let language: TargetLanguage?

    var body: some View {
        let host = incoming.hostID
        InterpreterCard {
            VStack(alignment: .leading, spacing: 16) {
                InterpreterSectionHeading(
                    title: "听朋友", subtitle: "保留外语原文，同步查看中文",
                    symbol: "captions.bubble.fill", color: InterpreterStyle.listening
                )
                Divider()
                HStack {
                    Text("\(language?.title ?? "尚未选择语言") → 中文 · \(incoming.provider.title)")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    listeningStatus
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        if incoming.captions.rows.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(incoming.captions.rows) { row in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(row.original)
                                            .font(.system(size: 15))
                                            .foregroundStyle(.secondary)
                                            .lineSpacing(3)
                                        Text(row.chinese.isEmpty ? (incoming.isActive ? "正在翻译…" : "继续听朋友后翻译") : row.chinese)
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundStyle(row.chinese.isEmpty ? .secondary : .primary)
                                            .lineSpacing(5)
                                        if let error = row.translationError {
                                            Label(error, systemImage: "exclamationmark.triangle")
                                                .font(.caption).foregroundStyle(.secondary)
                                        } else if row.translatedRevision < row.revision, !row.chinese.isEmpty {
                                            Label("中文正在跟随原文更新…", systemImage: "arrow.triangle.2.circlepath")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(16)
                                    .background(InterpreterStyle.listening.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                                    .id(row.id)
                                }
                            }
                        }
                    }
                    .frame(height: 332)
                    .onChange(of: incoming.captions.rows) {
                        if let id = incoming.captions.rows.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
                Divider()
                Label(incoming.status, systemImage: "iphone.radiowaves.left.and.right")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let failure = incoming.failure {
                    InterpreterNotice(message: failure)
                }
            }
        }
        .background {
            Color.clear.frame(width: 0, height: 0)
                .translationTask(incoming.configuration) { session in
                    await incoming.runTranslation(session, host: host)
                }
                .id(host)
        }
    }

    @ViewBuilder
    private var listeningStatus: some View {
        if incoming.failure != nil {
            InterpreterStatus(title: "需要重试", symbol: "exclamationmark.circle")
        } else if incoming.isPaused {
            InterpreterStatus(title: "已暂停", symbol: "pause.circle")
        } else if incoming.isStarting {
            InterpreterStatus(title: "准备中", symbol: "ellipsis.circle", color: InterpreterStyle.listening)
        } else if incoming.isActive {
            InterpreterStatus(title: "正在听", symbol: "waveform", color: InterpreterStyle.listening)
        } else {
            InterpreterStatus(title: "待收听", symbol: "ear")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(InterpreterStyle.listening)
                .frame(width: 72, height: 72)
                .background(InterpreterStyle.listening.opacity(0.08), in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(incoming.isStarting || incoming.isActive ? "等待朋友开口…" : "从听懂第一句话开始")
                    .font(.system(size: 18, weight: .medium))
                Text("让电脑麦克风听清对方的声音\n点击“听朋友”，原文和中文会出现在这里")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(.horizontal, 12)
    }
}
