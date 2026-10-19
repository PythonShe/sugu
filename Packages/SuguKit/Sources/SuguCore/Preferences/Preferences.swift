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
    public var pinyinScheme: PinyinScheme = .fullPinyin
    public var chineseScript: ChineseScript = .simplified
    public var fuzzyPinyin: Set<FuzzyPinyin> = []
    public var punctuationWidth: PunctuationWidth = .automatic
    public var useGrammarModel = true
    public var latinAllowList: [String] = []

    // MARK: Japanese
    public var kanaInput = false
    public var japanesePunctuation: JapanesePunctuationStyle = .touten
    public var japanesePredictions = true
    public var typoCorrection = true
    public var fullWidthSpace = false
    public var zenzaiEnabled = false

    // MARK: Apps
    public var rememberModePerApp = true
    public var appRules: [String: AppRule] = [:]

    // MARK: Learning
    public var learningEnabled = true
    public var learnedWordExpiryDays = 180
    public var noLearnApps: [String] = Preferences.defaultNoLearnApps

    public init() {}

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
        load(.pinyinScheme, into: &pinyinScheme)
        load(.chineseScript, into: &chineseScript)
        load(.fuzzyPinyin, into: &fuzzyPinyin)
        load(.punctuationWidth, into: &punctuationWidth)
        load(.useGrammarModel, into: &useGrammarModel)
        load(.latinAllowList, into: &latinAllowList)
        load(.kanaInput, into: &kanaInput)
        load(.japanesePunctuation, into: &japanesePunctuation)
        load(.japanesePredictions, into: &japanesePredictions)
        load(.typoCorrection, into: &typoCorrection)
        load(.fullWidthSpace, into: &fullWidthSpace)
        load(.zenzaiEnabled, into: &zenzaiEnabled)
        load(.rememberModePerApp, into: &rememberModePerApp)
        load(.appRules, into: &appRules)
        load(.learningEnabled, into: &learningEnabled)
        load(.learnedWordExpiryDays, into: &learnedWordExpiryDays)
        load(.noLearnApps, into: &noLearnApps)
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
        "io.alacritty",
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

public enum ChineseScript: String, Codable, Sendable, CaseIterable {
    case simplified
    case traditional
    case traditionalTaiwan
    case traditionalHongKong
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

    public init(defaultMode: InputMode? = nil, escapeSwitchesToEnglish: Bool = false) {
        self.defaultMode = defaultMode
        self.escapeSwitchesToEnglish = escapeSwitchesToEnglish
    }
}
