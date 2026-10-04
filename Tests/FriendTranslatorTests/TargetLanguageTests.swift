import Foundation
import Testing
@preconcurrency import Translation
@testable import FriendTranslator

// 固定语言仅是测试样本，产品列表完全来自系统查询。
extension TargetLanguage {
    static let english = TargetLanguage(identifier: "en")
    static let russian = TargetLanguage(identifier: "ru")
}

@Test func languageMatchingUsesAvailableRegionalResources() {
    let polish = TargetLanguage(identifier: "pl")
    let japanese = TargetLanguage(identifier: "ja")
    #expect(polish.matchingIdentifier(in: ["en-US", "pl-PL", "ja-JP"]) == "pl-PL")
    #expect(japanese.matchingIdentifier(in: ["pl-PL", "ja-JP"]) == "ja-JP")
    #expect(japanese.matchingIdentifier(in: ["pl-PL"]) == nil)
    #expect(TargetLanguage.english.matchingIdentifier(in: ["en-GB"]) == "en-GB")
    #expect(TargetLanguage(identifier: "zh-Hant").matchingIdentifier(in: ["zh-CN"]) == nil)
    #expect(polish.title.contains("波兰"))
    #expect(japanese.title.contains("日本") || japanese.title.contains("日语"))
}

@Test @MainActor func catalogRequiresInstalledTranslationInBothDirections() async {
    let supported = ["zh-Hans", "en", "ja", "pl", "ru", "fr", "ja"].map { Locale.Language(identifier: $0) }
    let installed = await SystemLanguages.installed(from: supported) { source, target in
        let foreign = source.languageCode?.identifier == "zh" ? target : source
        switch foreign.languageCode?.identifier {
        case "ja", "pl": return .installed
        case "en": return source.languageCode?.identifier == "zh" ? .installed : .supported
        case "ru": return .supported
        default: return .unsupported
        }
    }
    #expect(Set(installed.map(\.id)) == ["ja", "pl"])
    #expect(installed.count == 2)
}

@Test @MainActor func downloadedLanguagesAppearOnRefreshAndKeepSelection() async {
    var installed: [TargetLanguage] = []
    let model = AppModel(listDevices: { [] }, listLanguages: { installed }, listVoices: { [] })
    await model.refreshLanguages()
    #expect(model.availableLanguages.isEmpty)
    #expect(model.language == nil)
    let polish = TargetLanguage(identifier: "pl")
    let japanese = TargetLanguage(identifier: "ja")
    installed = [polish]
    await model.refreshLanguages()
    #expect(model.language == polish)
    installed = [japanese, polish]
    await model.refreshLanguages()
    #expect(model.availableLanguages == installed)
    #expect(model.language == polish)
    model.selectLanguage(japanese)
    #expect(model.language == japanese)
    // 不允许绕过已下载列表选择不可用的语言。
    model.selectLanguage(.russian)
    #expect(model.language == japanese)
    model.editChinese("你好")
    installed = []
    await model.refreshLanguages()
    #expect(model.language == nil)
    #expect(model.draft.chinese == "你好")
    #expect(!model.draft.canPlay)
}

@Test @MainActor func cancelledLanguageRefreshKeepsPreviousCatalog() async throws {
    var pending: CheckedContinuation<[TargetLanguage], Never>?
    let model = AppModel(listDevices: { [] }, listLanguages: {
        await withCheckedContinuation { pending = $0 }
    }, listVoices: { [] })
    let refresh = Task { await model.refreshLanguages() }
    while pending == nil { await Task.yield() }
    refresh.cancel()
    pending?.resume(returning: [.english])
    await refresh.value
    #expect(model.availableLanguages.isEmpty)
    #expect(model.language == nil)
    #expect(!model.isRefreshingLanguages)
}
