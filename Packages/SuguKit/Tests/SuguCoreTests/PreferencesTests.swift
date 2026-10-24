import Foundation
import Testing
@testable import SuguCore

struct PreferencesTests {
    @Test func missingKeysFallBackToDefaults() throws {
        let data = Data(#"{"candidatesPerPage": 5, "unknownKey": true}"#.utf8)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(decoded.candidatesPerPage == 5)
        #expect(decoded.pinyinScheme == .fullPinyin)
        #expect(decoded.noLearnApps == Preferences.defaultNoLearnApps)
    }

    @Test func decodedValuesStayWithinWhatSettingsAllows() throws {
        let data = Data(#"{"enabledModes": ["english", "english"], "candidatesPerPage": 40, "candidateFontSize": 99, "learnedWordExpiryDays": 1}"#.utf8)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(decoded.enabledModes == Preferences().enabledModes)
        #expect(decoded.candidatesPerPage == 10)
        #expect(decoded.candidateFontSize == 28)
        #expect(decoded.learnedWordExpiryDays == 30)
    }

    @Test func decodedModesKeepTheirOrderWithEnglishLast() throws {
        let data = Data(#"{"enabledModes": ["english", "japanese", "japanese"], "candidateFontSize": 13, "learnedWordExpiryDays": 400}"#.utf8)
        let decoded = try JSONDecoder().decode(Preferences.self, from: data)
        #expect(decoded.enabledModes == [.japanese, .english])
        #expect(decoded.candidateFontSize == 14)
        #expect(decoded.learnedWordExpiryDays == 0)
    }

    @Test func roundTrip() throws {
        var preferences = Preferences()
        preferences.fuzzyPinyin = [.zZh, .nL]
        preferences.appRules["com.example"] = AppRule(defaultMode: .japanese)
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(Preferences.self, from: data) == preferences)
    }

    @Test func defaultsFollowThePreferredLanguages() {
        #expect(Preferences(preferredLanguages: ["en-US", "ja-JP", "zh-Hans-CN"]).enabledModes == [.japanese, .chinese, .english])
        #expect(Preferences(preferredLanguages: ["zh-Hans-CN", "ja-JP"]).enabledModes == [.chinese, .japanese, .english])
        #expect(Preferences(preferredLanguages: ["zh-Hant-TW"]).chineseScript == .traditionalTaiwan)
        #expect(Preferences(preferredLanguages: ["zh-Hant-HK"]).chineseScript == .traditionalHongKong)
        #expect(Preferences(preferredLanguages: ["zh-Hant"]).chineseScript == .traditional)
        #expect(Preferences(preferredLanguages: ["en-US"]) == Preferences())
    }

    @MainActor @Test func firstLaunchKeepsItsDefaults() throws {
        let suite = "sugu-preferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = PreferencesStore(defaults: defaults, preferredLanguages: ["ja-JP"])
        #expect(PreferencesStore(defaults: defaults, preferredLanguages: ["zh-Hans-CN"]).preferences.enabledModes.first == .japanese)
    }

    @Test func terminalsDefaultToEnglish() {
        let rule = Preferences().rule(for: "com.apple.Terminal")
        #expect(rule.defaultMode == .english)
        #expect(rule.escapeSwitchesToEnglish)
    }

    @Test func passwordManagersDoNotLearn() {
        #expect(!Preferences().learns(in: "com.1password.1password"))
        #expect(Preferences().learns(in: "com.apple.TextEdit"))
    }
}
