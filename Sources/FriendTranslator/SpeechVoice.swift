import AVFoundation
import Foundation

struct SpeechVoice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let languageIdentifier: String
    var quality = ""

    var title: String {
        let region = Locale(identifier: "zh-Hans").localizedString(forIdentifier: languageIdentifier)
            ?? languageIdentifier
        return [name, region, quality].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func available() -> [SpeechVoice] {
        AVSpeechSynthesisVoice.speechVoices().compactMap { voice in
            guard AVSpeechSynthesisVoice(identifier: voice.identifier) != nil else { return nil }
            let quality: String
            switch voice.quality {
            case .enhanced: quality = "优化音质"
            case .premium: quality = "高音质"
            default: quality = "标准"
            }
            return SpeechVoice(id: voice.identifier, name: voice.name, languageIdentifier: voice.language, quality: quality)
        }
    }

    static func matching(_ voices: [SpeechVoice], language: TargetLanguage) -> [SpeechVoice] {
        voices.filter { language.matchingIdentifier(in: [$0.languageIdentifier]) != nil }
            .sorted { $0.title == $1.title ? $0.id < $1.id : $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
