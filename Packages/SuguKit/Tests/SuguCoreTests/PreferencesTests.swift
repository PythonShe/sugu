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

    @Test func roundTrip() throws {
        var preferences = Preferences()
        preferences.fuzzyPinyin = [.zZh, .nL]
        preferences.appRules["com.example"] = AppRule(defaultMode: .japanese)
        let data = try JSONEncoder().encode(preferences)
        #expect(try JSONDecoder().decode(Preferences.self, from: data) == preferences)
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
