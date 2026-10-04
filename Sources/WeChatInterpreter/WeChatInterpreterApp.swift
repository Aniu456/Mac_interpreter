import AppKit
import SwiftUI

@main
struct WeChatInterpreterApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("WeChat 语音翻译 · 手机免提模式", id: "main") {
            ContentView(model: model)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    model.stop()
                }
                .onDisappear { model.stop() }
        }
        .defaultSize(width: 1000, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("立即停止") { model.stop() }
                    .keyboardShortcut(".", modifiers: .command)
            }
        }
        Settings {
            SettingsView(model: model)
        }
    }
}
