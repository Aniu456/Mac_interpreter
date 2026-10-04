import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var key = ""
    @State private var message = "Key 仅保存在本机钥匙串。"
    @State private var grokMessage = GrokClient.hasLogin ? "已保存浏览器登录，可测试连接。" : "尚未登录"
    @State private var operation: Task<Void, Never>?
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                InterpreterSectionHeading(
                    title: "翻译设置", subtitle: "管理语音识别与翻译服务连接",
                    symbol: "slider.horizontal.3", color: InterpreterStyle.accent
                )
                Spacer()
            }
            .padding(24)
            Divider()
            if model.isBusy || model.isHearingFriend {
                Label("正在收听或播报，请先在主窗口停止，再修改设置。", systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24).padding(.top, 16)
            }
            Form {
                Section("语音识别") {
                    Toggle("英文使用 Parakeet 本地识别", isOn: $model.localEnglishRecognition)
                    Text("首次使用下载模型，之后在本机识别英文。中文及其他外语保留 Apple 识别。")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("允许 Apple 在线语音识别", isOn: $model.allowNetworkRecognition)
                    Text("关闭时仅使用本地语音模型；开启后 Apple 可能处理音频。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("DeepSeek · API Key") {
                    SecureField("输入 API Key", text: $key)
                    Picker("翻译模型", selection: $model.deepSeekModel) {
                        ForEach(DeepSeekModel.allCases) { Text($0.title).tag($0) }
                    }
                    HStack {
                        Button("保存 Key") {
                            do { try DeepSeekKeychain.save(key); key = ""; message = "Key 已保存；尚未测试连接。" }
                            catch { message = error.localizedDescription }
                        }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("测试连接") { test(.deepSeek) }
                        Button("删除 Key", role: .destructive) {
                            do { try DeepSeekKeychain.delete(); key = ""; message = "Key 已删除。" }
                            catch { message = error.localizedDescription }
                        }
                    }
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Section("Grok · 浏览器登录") {
                    HStack {
                        Button("在浏览器中登录") {
                            run {
                                grokMessage = "请在浏览器中完成官方授权…"
                                do { try await GrokClient.login(); grokMessage = "登录已保存，可测试翻译连接。" }
                                catch { grokMessage = Task.isCancelled ? "登录已取消。" : error.localizedDescription }
                            }
                        }
                        Button("测试连接") { test(.grok) }
                        Button("退出登录") {
                            run {
                                do { try await GrokClient.logout(); grokMessage = "已退出登录。" }
                                catch { grokMessage = error.localizedDescription }
                            }
                        }
                    }
                    Text(grokMessage).font(.caption).foregroundStyle(.secondary)
                    Text("通过官方 Grok Build 组件授权，需账户具备对应使用权限。组件在本机保存登录和会话记录。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Text("选择 DeepSeek 或 Grok 后，当前原文及最近几段上下文会发送给对应服务；不上传麦克风音频。测试连接会发送一句“你好”。AI 译文仍请结合原文核对。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .disabled(working || model.isBusy || model.isHearingFriend)
            .overlay(alignment: .bottomTrailing) {
                if working {
                    HStack { ProgressView().controlSize(.small); Button("取消") { operation?.cancel() } }
                        .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).padding()
                }
            }
        }
        .tint(InterpreterStyle.accent)
        .background(InterpreterStyle.canvas)
        .frame(width: 600, height: 740)
        .onDisappear { operation?.cancel(); key = "" }
    }
    private func run(_ body: @escaping @MainActor () async -> Void) {
        working = true
        operation = Task { await body(); working = false; operation = nil }
    }
    private func test(_ provider: TranslationProvider) {
        run {
            if provider == .deepSeek { message = "正在测试…" } else { grokMessage = "正在测试…" }
            do {
                let result = try await AITranslator().translate(TranslationInput(text: "你好", source: "zh-Hans", target: "en"), provider: provider, model: model.deepSeekModel)
                let success = "连接成功：\(result)"
                if provider == .deepSeek { message = success } else { grokMessage = success }
            } catch {
                let failure = Task.isCancelled ? "测试已取消。" : error.localizedDescription
                if provider == .deepSeek { message = failure } else { grokMessage = failure }
            }
        }
    }
}
