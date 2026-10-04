# 朋友之间语言翻译器

一个面向朋友交流的简单 macOS 翻译工具：通过电脑麦克风听取朋友说的话，显示识别原文和中文翻译。

核心流程是 **听取语音 → 识别文字 → 显示翻译**，适合面对面交流或听取电脑旁清晰播放的外语声音。也可以输入或说出中文，翻译后播放外语回复。

## 开始使用

1. 允许麦克风和语音识别权限，准备所需的语言资源。
2. 选择对方的语言和翻译服务。
3. 点击“听朋友”，让电脑麦克风听清对方的声音，查看原文和中文翻译。
4. 暂时不需要收听时，再点同一按钮“暂停收听”；字幕保留，点“听朋友”即可继续。回复时直接点“我来说”，收听自动暂停，译文播放后自动恢复。主界面不再单独提供“停止”按钮；临时中断录音、翻译或播报可按 Esc。

需要回复时，可点击“我来说”，说中文后点击“说完了”；也可以直接输入中文，再翻译并播放。播报期间暂停收音，播放结束后继续听译。

## 功能

- 显示外语原文和中文翻译，保留当前会话中的近期字幕。
- 支持 Apple 系统翻译，也可配置 DeepSeek 或 Grok。
- 英文可使用 Parakeet 本地识别；中文及其他语言使用 Apple 语音识别。
- 支持中文文字输入、语音回复和系统朗读音色选择。
- 识别或翻译失败时保留已有文字，方便检查与重试。

语言列表根据系统已安装的双向翻译资源生成。翻译语言包、语音识别资源和朗读声音需要分别准备；英文 Parakeet 模型在首次使用时下载。

## 翻译服务与隐私

- **Apple**：使用系统翻译语言包。默认要求本机语音识别；在设置中允许在线识别后，音频可能交由 Apple 服务处理。
- **DeepSeek**：在设置中保存 API Key，密钥存入 macOS 钥匙串。
- **Grok**：通过官方 Grok Build 组件进行浏览器授权，需要对应账户权限及完整的组件配置。

选择 DeepSeek 或 Grok 后，识别文字和有限的前文会发送给相应服务，可能产生服务用量。应用不保存录音，界面字幕保留在内存中；Grok 官方组件会在本机保存登录和会话记录。

识别和翻译效果取决于说话清晰度、环境噪声和语言资源。应用通过麦克风收音；说中文或播放译文时，外语听译会暂停。

## 从源码运行

需要 macOS 15+、Swift 6.1+ / Xcode 命令行工具和 Git LFS。Swift 包依赖见 `Package.swift`，版本锁定在 `Package.resolved`。仓库内 Grok 组件为 Apple Silicon 版本。

使用 Xcode 时，打开根目录的 `FriendTranslator.xcodeproj`，等待依赖解析完成，选择 **FriendTranslator → My Mac**，点击 Run（`⌘ R`）。App target 已配置权限说明和 Grok 组件打包，采用本机开发用的 ad-hoc 签名。正式分发需另行配置签名与公证。不要只把源码目录作为文件夹打开。

也可使用命令行构建：

```sh
git clone git@github.com:Aniu456/Mac_interpreter.git friend_translator
cd friend_translator
git lfs pull
./scripts/build-app.sh
open dist/FriendTranslator.app
```

请通过 `.app` 启动。构建脚本默认生成本机使用的 ad-hoc 签名开发包，未公证。内部工程与模块名称为 `FriendTranslator`，应用 ID 为 `dev.benny.FriendTranslator`，项目目录为 `friend_translator`。

旧版升级后会保留语音识别偏好与音色选择，并兼容迁移本机 DeepSeek 密钥和 Grok 登录目录。新登录数据位于 `~/Library/Application Support/FriendTranslator/Grok`。应用 ID 改变后，macOS 可能重新请求麦克风、语音识别或钥匙串访问权限。

## 验证

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
swift test --disable-sandbox --cache-path .build/cache --scratch-path .build/fix-verification
```

自动测试用于检查数据处理和状态切换；实际收音、识别准确度和翻译效果需要在使用中验证。参见[验收记录](docs/acceptance.md)。文档中的早期微信通话与音频路由调查仅为历史记录。

## 许可证

见 [LICENSE](LICENSE)。第三方 Grok 组件说明见 [Vendor/Grok](Vendor/Grok/README.md)。
