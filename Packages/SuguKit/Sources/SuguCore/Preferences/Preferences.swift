import Foundation

/// Every user-facing option, with the defaults a fresh install uses.
/// Persisted by `PreferencesStore`; unknown or missing keys fall back to
/// these defaults, so adding an option never breaks stored settings.
public struct Preferences: Codable, Sendable, Equatable {
    // MARK: General
    public var enabledModes: [InputMode] = [.chinese, .japanese, .english]
    public var englishToggle: EnglishToggle = .shiftTap
    public var showModeIndicator = true
    public var candidateLayout: CandidateLayout = .vertical
    public var candidatesPerPage = 7
    public var candidateFontSize = 16.0
    public var readingHints = false
    public var pauseGatedWindow = false
    public var leftContextRanking = true
    public var documentVocabulary = false

    // MARK: Chinese
    public var chineseKeyboard: ChineseKeyboard = .pinyin
    public var zhuyinLayout: ZhuyinLayout = .standard
    public var pinyinScheme: PinyinScheme = .fullPinyin
    public var chineseScript: ChineseScript = .simplified
    public var fuzzyPinyin: Set<FuzzyPinyin> = []
    public var punctuationWidth: PunctuationWidth = .automatic
    public var useGrammarModel = true
    public var chineseDictionary: ChineseDictionary = .wanxiang
    public var latinAllowList: [String] = []

    // MARK: Japanese
    public var kanaInput = false
    public var japanesePunctuation: JapanesePunctuationStyle = .touten
    public var japanesePredictions = true
    public var liveConversion = false
    public var typoCorrection = true
    public var fullWidthSpace = false
    public var zenzaiEnabled = false

    // MARK: Language model (ADR 0004)
    public var languageModel: LanguageModelLevel = .off
    public var modelForSelection = true
    public var modelForConversion = false
    public var modelForTranslation = false

    // MARK: Apps
    public var rememberModePerApp = true
    public var appRules: [String: AppRule] = [:]

    // MARK: Learning
    public var learningEnabled = true
    public var learnedWordExpiryDays = 180
    /// Learn the user's character n-grams and rank with them (D-079).
    public var learnsPhrases = true
    public var noLearnApps: [String] = Preferences.defaultNoLearnApps

    // MARK: Sync
    /// Folder the user picked for dictionary sync; nil when sync is off.
    public var syncFolderPath: String?
    /// Learned words travel through the sync folder only when opted in.
    public var syncLearnedWords = false

    public init() {}

    /// The defaults for someone who reads `preferredLanguages` (BCP 47, most
    /// preferred first): the first Chinese or Japanese among them leads the
    /// modes, and a Traditional Chinese one sets the script.
    public init(preferredLanguages: [String]) {
        self.init()
        let languages = preferredLanguages.map(Locale.Language.init(identifier:))
        guard let first = languages.first(where: { ["zh", "ja"].contains($0.languageCode?.identifier) }) else { return }
        if first.languageCode?.identifier == "ja" {
            enabledModes = [.japanese, .chinese, .english]
            return
        }
        switch (first.script?.identifier, first.region?.identifier) {
        case (_, "TW"): chineseScript = .traditionalTaiwan
        case (_, "HK"), (_, "MO"): chineseScript = .traditionalHongKong
        case ("Hant", _): chineseScript = .traditional
        default: break
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func load<T: Decodable>(_ key: CodingKeys, into value: inout T) {
            if let decoded = try? container.decodeIfPresent(T.self, forKey: key) { value = decoded }
        }
        load(.enabledModes, into: &enabledModes)
        load(.englishToggle, into: &englishToggle)
        load(.showModeIndicator, into: &showModeIndicator)
        load(.candidateLayout, into: &candidateLayout)
        load(.candidatesPerPage, into: &candidatesPerPage)
        load(.candidateFontSize, into: &candidateFontSize)
        load(.readingHints, into: &readingHints)
        load(.pauseGatedWindow, into: &pauseGatedWindow)
        load(.leftContextRanking, into: &leftContextRanking)
        load(.documentVocabulary, into: &documentVocabulary)
        load(.chineseKeyboard, into: &chineseKeyboard)
        load(.zhuyinLayout, into: &zhuyinLayout)
        load(.pinyinScheme, into: &pinyinScheme)
        load(.chineseScript, into: &chineseScript)
        load(.fuzzyPinyin, into: &fuzzyPinyin)
        load(.punctuationWidth, into: &punctuationWidth)
        load(.useGrammarModel, into: &useGrammarModel)
        load(.chineseDictionary, into: &chineseDictionary)
        load(.latinAllowList, into: &latinAllowList)
        load(.kanaInput, into: &kanaInput)
        load(.japanesePunctuation, into: &japanesePunctuation)
        load(.japanesePredictions, into: &japanesePredictions)
        load(.liveConversion, into: &liveConversion)
        load(.typoCorrection, into: &typoCorrection)
        load(.fullWidthSpace, into: &fullWidthSpace)
        load(.zenzaiEnabled, into: &zenzaiEnabled)
        load(.languageModel, into: &languageModel)
        load(.modelForSelection, into: &modelForSelection)
        load(.modelForConversion, into: &modelForConversion)
        load(.modelForTranslation, into: &modelForTranslation)
        load(.rememberModePerApp, into: &rememberModePerApp)
        load(.appRules, into: &appRules)
        load(.learningEnabled, into: &learningEnabled)
        load(.learnedWordExpiryDays, into: &learnedWordExpiryDays)
        load(.learnsPhrases, into: &learnsPhrases)
        load(.noLearnApps, into: &noLearnApps)
        load(.syncFolderPath, into: &syncFolderPath)
        load(.syncLearnedWords, into: &syncLearnedWords)
    }

    /// Password managers: Sugu neither learns from nor reads text in them.
    public static let defaultNoLearnApps = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "com.dashlane.dashlanephonefinal",
    ]

    /// Terminals, where Sugu starts in English and Esc returns to English.
    public static let terminalApps: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.github.wez.wezterm",
    ]

    /// The rule for an app, including built-in behavior for terminals.
    public func rule(for bundleID: String?) -> AppRule {
        guard let bundleID else { return AppRule() }
        if let rule = appRules[bundleID] { return rule }
        if Self.terminalApps.contains(bundleID) {
            return AppRule(defaultMode: .english, escapeSwitchesToEnglish: true)
        }
        return AppRule()
    }

    /// Whether Sugu may read the field's text (left context, document
    /// vocabulary, reconversion) in this app.
    public func readsContext(in bundleID: String?) -> Bool {
        guard let bundleID else { return true }
        return !noLearnApps.contains(bundleID)
    }

    public func learns(in bundleID: String?) -> Bool {
        guard learningEnabled else { return false }
        guard let bundleID else { return true }
        return !noLearnApps.contains(bundleID)
    }
}

public enum EnglishToggle: String, Codable, Sendable, CaseIterable {
    /// Tapping Shift alone toggles English.
    case shiftTap
    /// Caps Lock toggles English.
    case capsLock
    case none
}

public enum CandidateLayout: String, Codable, Sendable, CaseIterable {
    case vertical
    case horizontal
}

/// The Chinese dictionary: the bundled one, or rime-ice when the user has
/// downloaded it (GPL-3.0, so never bundled).
public enum ChineseDictionary: String, Codable, Sendable, CaseIterable {
    case wanxiang
    case rimeIce
}

public enum ChineseScript: String, Codable, Sendable, CaseIterable {
    case simplified
    case traditional
    case traditionalTaiwan
    case traditionalHongKong
    /// Japanese kanji forms (shinjitai), for Chinese words in Japanese text.
    case japanese

    /// Traditional Chinese, as written in Taiwan and Hong Kong, quotes with
    /// corner brackets.
    public var usesCornerQuotes: Bool {
        self == .traditional || self == .traditionalTaiwan || self == .traditionalHongKong
    }
}

/// How Chinese is typed: pinyin letters, or Zhuyin symbols.
public enum ChineseKeyboard: String, Codable, Sendable, CaseIterable {
    case pinyin
    case zhuyin
}

/// Where the Zhuyin symbols are on the keyboard: the standard (大千)
/// layout, Eten's (倚天), or IBM's.
public enum ZhuyinLayout: String, Codable, Sendable, CaseIterable {
    case standard
    case eten
    case ibm
}

/// Pinyin spelling schemes. Double-pinyin layouts map each syllable to two
/// keys; their spelling rules come from the bundled schema data.
public enum PinyinScheme: String, Codable, Sendable, CaseIterable {
    case fullPinyin
    case xiaohe
    case ziranma
    case microsoft
    case sogou
    case ziguang
    case abc
    case pinyinPlusPlus
}

/// Pairs of sounds the user treats as the same.
public enum FuzzyPinyin: String, Codable, Sendable, CaseIterable {
    case zZh, cCh, sSh, nL, fH, rL, rY, kG, enEng, inIng
}

/// Per-app behavior.
public struct AppRule: Codable, Sendable, Equatable {
    /// Mode to enter when the app gains focus; nil uses the remembered or
    /// global mode.
    public var defaultMode: InputMode?
    /// Esc commits or cancels the composition, then switches to English.
    public var escapeSwitchesToEnglish = false
    /// Chinese characters in this app; nil uses the global choice.
    public var chineseScript: ChineseScript?

    public init(defaultMode: InputMode? = nil, escapeSwitchesToEnglish: Bool = false, chineseScript: ChineseScript? = nil) {
        self.defaultMode = defaultMode
        self.escapeSwitchesToEnglish = escapeSwitchesToEnglish
        self.chineseScript = chineseScript
    }
}
