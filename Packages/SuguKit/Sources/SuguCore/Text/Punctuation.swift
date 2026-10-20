/// How Chinese punctuation chooses between full and half width.
public enum PunctuationWidth: String, Codable, Sendable, CaseIterable {
    /// Half-width after Latin letters and digits, full-width otherwise.
    case automatic
    case full
    case half
}

/// Japanese comma/period pair.
public enum JapanesePunctuationStyle: String, Codable, Sendable, CaseIterable {
    case touten     // 、。
    case commaPeriod // ，．
    case commaMaru  // ，。
    case toutenPeriod // 、．

    public var comma: String { self == .touten || self == .toutenPeriod ? "、" : "，" }
    public var period: String { self == .touten || self == .commaMaru ? "。" : "．" }

    /// What a symbol key adds to a romaji composition, as in the system
    /// Japanese input method: the long-vowel mark, corner brackets, the
    /// middle dot and wave dash, and full width for the rest. Letters and
    /// digits pass through for the romaji table and the converter.
    public func romajiInput(for character: Character) -> String {
        switch character {
        case ",": comma
        case ".": period
        case "-": "ー"
        case "[": "「"
        case "]": "」"
        case "/": "・"
        case "~": "〜"
        default:
            character.isASCII && !character.isLetter && !character.isNumber
                ? WidthConversion.fullWidth(String(character))
                : String(character)
        }
    }
}

/// Maps punctuation keys to output in Chinese mode, tracking open/close state
/// of paired quotes.
public struct ChinesePunctuator: Sendable {
    public var width: PunctuationWidth
    /// Traditional Chinese quotes with corner brackets (「」 and 『』) and
    /// writes the dollar sign for `$`; Simplified uses “” ‘’ and ￥.
    public var script: ChineseScript = .simplified
    private var doubleQuoteOpen = false
    private var singleQuoteOpen = false

    public init(width: PunctuationWidth = .automatic) {
        self.width = width
    }

    /// Characters handled as punctuation in Chinese mode.
    public static func handles(_ character: Character) -> Bool {
        fullWidth[character] != nil || character == "\"" || character == "'"
    }

    /// Output for a punctuation key, given the character before the caret.
    public mutating func output(for character: Character, after previous: Character?) -> String {
        let useHalf: Bool
        switch width {
        case .half: useHalf = true
        case .full: useHalf = false
        case .automatic: useHalf = previous?.isASCIILetterOrDigit ?? false
        }
        if useHalf, Self.widthSensitive.contains(character) {
            return String(character)
        }
        let corners = script.usesCornerQuotes
        switch character {
        case "\"":
            doubleQuoteOpen.toggle()
            return doubleQuoteOpen ? (corners ? "「" : "“") : (corners ? "」" : "”")
        case "'":
            singleQuoteOpen.toggle()
            return singleQuoteOpen ? (corners ? "『" : "‘") : (corners ? "』" : "’")
        case "$" where corners:
            return "＄"
        default:
            return Self.fullWidth[character] ?? String(character)
        }
    }

    public mutating func reset() {
        doubleQuoteOpen = false
        singleQuoteOpen = false
    }

    /// Sentence punctuation that stays half-width after Latin text and
    /// digits ("3.14", "e.g.", "v2,").
    private static let widthSensitive: Set<Character> = [",", ".", ":", ";", "?", "!", "\"", "'", "(", ")"]

    private static let fullWidth: [Character: String] = [
        ",": "，", ".": "。", "?": "？", "!": "！", ":": "：", ";": "；",
        "(": "（", ")": "）", "[": "【", "]": "】", "{": "｛", "}": "｝",
        "<": "《", ">": "》", "\\": "、", "~": "～", "`": "·",
        "^": "……", "_": "——", "$": "￥",
    ]
}
