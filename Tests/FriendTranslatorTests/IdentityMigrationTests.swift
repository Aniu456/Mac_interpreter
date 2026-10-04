import Foundation
import Testing
@testable import FriendTranslator

@Test func legacyPreferencesKeepCurrentChoicesAndMigrateOnlyOnce() throws {
    let oldDomain = "FriendTranslatorTests.old.\(UUID().uuidString)"
    let newDomain = "FriendTranslatorTests.new.\(UUID().uuidString)"
    let old = try #require(UserDefaults(suiteName: oldDomain))
    let current = try #require(UserDefaults(suiteName: newDomain))
    defer {
        old.removePersistentDomain(forName: oldDomain)
        current.removePersistentDomain(forName: newDomain)
    }
    old.set(true, forKey: "allowNetworkRecognition")
    old.set(false, forKey: "localEnglishRecognition")
    old.set(["en": "example-voice"], forKey: "speechVoiceByLanguage")
    current.set(false, forKey: "allowNetworkRecognition")

    LegacyPreferences.migrate(to: current, from: oldDomain)
    #expect(current.bool(forKey: "allowNetworkRecognition") == false)
    #expect(current.object(forKey: "localEnglishRecognition") as? Bool == false)
    #expect(current.dictionary(forKey: "speechVoiceByLanguage")?["en"] as? String == "example-voice")
    #expect(old.dictionary(forKey: "speechVoiceByLanguage") != nil)

    current.removeObject(forKey: "speechVoiceByLanguage")
    LegacyPreferences.migrate(to: current, from: oldDomain)
    #expect(current.dictionary(forKey: "speechVoiceByLanguage") == nil)
}

@Test func grokMigrationPreservesOldDataAndDoesNotRestoreLoggedOutCredentials() throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent("FriendTranslatorTests-\(UUID().uuidString)")
    let old = root.appendingPathComponent("legacy/Grok")
    let current = root.appendingPathComponent("current/Grok")
    defer { try? files.removeItem(at: root) }
    try files.createDirectory(at: old, withIntermediateDirectories: true)
    let fixture = Data("synthetic migration fixture".utf8)
    try fixture.write(to: old.appendingPathComponent("auth.json"))

    try GrokClient.prepareHome(at: current, legacy: old)
    #expect(try Data(contentsOf: current.appendingPathComponent("auth.json")) == fixture)
    #expect(files.fileExists(atPath: old.appendingPathComponent("auth.json").path))
    let permissions = try files.attributesOfItem(atPath: current.path)[.posixPermissions] as? NSNumber
    #expect(permissions?.intValue == 0o700)

    try files.removeItem(at: current.appendingPathComponent("auth.json"))
    try GrokClient.prepareHome(at: current, legacy: old)
    #expect(!files.fileExists(atPath: current.appendingPathComponent("auth.json").path))
}

@Test func grokMigrationCreatesFreshHomeWithoutLegacyData() throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent("FriendTranslatorTests-\(UUID().uuidString)")
    defer { try? files.removeItem(at: root) }
    let current = root.appendingPathComponent("current/Grok")
    try GrokClient.prepareHome(at: current, legacy: root.appendingPathComponent("missing"))
    #expect(files.fileExists(atPath: current.path))
    #expect(!files.fileExists(atPath: current.appendingPathComponent("auth.json").path))
}
