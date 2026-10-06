import Foundation
@preconcurrency import Translation

struct TargetLanguage: Hashable, Identifiable, Sendable {
    let id: String

    init(identifier: String) {
        id = Locale.Language(identifier: identifier).minimalIdentifier
    }

    var localeLanguage: Locale.Language { Locale.Language(identifier: id) }
    var title: String {
        let chinese = Locale(identifier: "zh-Hans").localizedString(forIdentifier: id) ?? id
        let native = Locale(identifier: id).localizedString(forIdentifier: id) ?? id
        return chinese == native ? chinese : "\(chinese) · \(native)"
    }

    /// 识别地区和播报地区分别从各自的系统资源中选择，避免写死语言表。
    func matchingIdentifier(in identifiers: [String]) -> String? {
        let language = localeLanguage
        let matches = identifiers.sorted().filter {
            let candidate = Locale.Language(identifier: $0)
            return candidate.languageCode == language.languageCode && candidate.script == language.script
        }
        return matches.first { Locale.Language(identifier: $0).isEquivalent(to: language) } ?? matches.first
    }
}

@MainActor
enum SystemLanguages {
    static func installed() async -> [TargetLanguage] {
        let availability = LanguageAvailability()
        let supported = await availability.supportedLanguages
        return await installed(from: supported) { source, target in
            await availability.status(from: source, to: target)
        }
    }

    static func installed(
        from supported: [Locale.Language],
        status: (Locale.Language, Locale.Language) async -> LanguageAvailability.Status
    ) async -> [TargetLanguage] {
        let chinese = Locale.Language(identifier: "zh-Hans")
        var result = Set<TargetLanguage>()
        for language in supported {
            guard !Task.isCancelled else { return [] }
            guard language.languageCode != chinese.languageCode else { continue }
            // 两个方向都安装好，才提供给双向听译流程。
            guard await status(chinese, language) == .installed,
                  await status(language, chinese) == .installed else { continue }
            result.insert(TargetLanguage(identifier: language.minimalIdentifier))
        }
        let preferredLanguages = ["ru", "en"]
        return result.sorted {
            let left = preferredLanguages.firstIndex(of: $0.id) ?? preferredLanguages.count
            let right = preferredLanguages.firstIndex(of: $1.id) ?? preferredLanguages.count
            if left != right { return left < right }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
}
