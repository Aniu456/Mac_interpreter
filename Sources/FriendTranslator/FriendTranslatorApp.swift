import AppKit
import SwiftUI

@main
struct FriendTranslatorApp: App {
    @State private var model: AppModel

    init() {
        LegacyPreferences.migrate()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        Window("朋友之间语言翻译器", id: "main") {
            ContentView(model: model)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
                       let icon = NSImage(contentsOf: iconURL) {
                        NSApplication.shared.applicationIconImage = icon
                    }
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

enum LegacyPreferences {
    static func migrate(
        to defaults: UserDefaults = .standard,
        from domain: String = "dev.benny.WeChatInterpreter"
    ) {
        guard !defaults.bool(forKey: "didMigrateLegacyPreferences") else { return }
        let previous = defaults.persistentDomain(forName: domain) ?? [:]
        for key in ["allowNetworkRecognition", "localEnglishRecognition", "speechVoiceByLanguage"] {
            if defaults.object(forKey: key) == nil, let value = previous[key] {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: "didMigrateLegacyPreferences")
    }
}
