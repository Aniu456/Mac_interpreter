import Foundation

/// 使用官方 Grok Build 的浏览器 OAuth；不读取浏览器 Cookie 或冒充网页登录 API。
enum GrokClient {
    static var home: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WeChatInterpreter/Grok", isDirectory: true)
    }
    static var executable: URL? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/grok")
        return FileManager.default.isExecutableFile(atPath: bundled.path) ? bundled : nil
    }
    static var hasLogin: Bool { FileManager.default.fileExists(atPath: home.appendingPathComponent("auth.json").path) }

    static func environment(home: URL) -> [String: String] {
        // 仅传必要系统环境；不继承 API Key、模型代理或其他 harness 配置。
        let inherited = ProcessInfo.processInfo.environment
        var values = [String: String]()
        for key in ["HOME", "USER", "TMPDIR", "LANG", "HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY"] {
            values[key] = inherited[key]
        }
        values["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        values["GROK_HOME"] = home.path
        values["GROK_DISABLE_AUTOUPDATER"] = "1"
        for key in ["MEMORY", "SUBAGENTS", "WEB_FETCH", "WRITE_FILE", "TOOL_SEARCH", "LSP_TOOLS", "TELEMETRY_ENABLED", "TELEMETRY_TRACE_UPLOAD"] {
            values["GROK_\(key)"] = "0"
        }
        for harness in ["CURSOR", "CLAUDE", "CODEX"] {
            for feature in ["SKILLS", "RULES", "AGENTS", "MCPS", "HOOKS", "SESSIONS"] {
                values["GROK_\(harness)_\(feature)_ENABLED"] = "0"
            }
        }
        return values
    }

    static func translationArguments(_ input: TranslationInput) throws -> [String] {
        ["--single", try input.payload(), "--system-prompt-override", input.instruction,
         "--verbatim", "--output-format", "json", "--tools", "", "--deny", "*",
         "--permission-mode", "dontAsk", "--max-turns", "1",
         "--no-plan", "--no-subagents", "--disable-web-search"]
    }

    static func translate(_ input: TranslationInput) async throws -> String {
        guard hasLogin else { throw InterpreterError("请先在设置中通过浏览器登录 Grok。") }
        guard !input.text.isEmpty, input.text.count <= 4000 else { throw InterpreterError("原文为空或过长，请分句重试。") }
        let data = try await run(arguments: translationArguments(input), timeout: 60)
        return try decode(data)
    }
    static func decode(_ data: Data) throws -> String {
        struct Result: Decodable { let text: String; let stopReason: String }
        guard let result = try? JSONDecoder().decode(Result.self, from: data), result.stopReason == "end_turn",
              !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InterpreterError("Grok 未返回完整译文，请重试。")
        }
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func login() async throws {
        _ = try await run(arguments: ["login", "--oauth"], timeout: 300)
        guard hasLogin else { throw InterpreterError("浏览器授权尚未完成，请重试。") }
    }
    static func logout() async throws { _ = try await run(arguments: ["logout"], timeout: 20) }

    static func run(arguments: [String], timeout: TimeInterval) async throws -> Data {
        guard let executable else { throw InterpreterError("缺少官方 Grok 登录组件，请使用完整应用包。") }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("interpreter-grok-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment(home: home)
        process.currentDirectoryURL = workspace
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        try Task.checkCancellation()
        try process.run()
        let output = Task.detached { try pipe.fileHandleForReading.readToEnd() ?? Data() }
        return try await withTaskCancellationHandler {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
            }
            if process.isRunning {
                process.terminate()
                try? await Task.sleep(for: .milliseconds(300))
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            let data = try await output.value
            try Task.checkCancellation()
            guard Date() < deadline else { throw InterpreterError("Grok 请求超时，请检查网络或重试浏览器登录。") }
            guard process.terminationStatus == 0 else {
                throw InterpreterError("Grok 未完成请求（\(process.terminationStatus)）。请检查网络、登录状态和账户的 Grok Build 使用权限。")
            }
            return data
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}
