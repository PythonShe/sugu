import Foundation

/// Zhuyin (Bopomofo): its symbols, the standard keyboard (大千), and the
/// pinyin of a syllable, with which librime's pinyin dictionary is read.
/// Written by Sugu from the standard tables.
public enum Zhuyin {
    public enum Tone: Int, Sendable, CaseIterable {
        case first = 1, second, third, fourth, neutral

        /// The mark written with a syllable; the first tone has none, and
        /// the neutral tone's dot is written before the syllable.
        public var mark: Character? {
            switch self {
            case .first: nil
            case .second: "ˊ"
            case .third: "ˇ"
            case .fourth: "ˋ"
            case .neutral: "˙"
            }
        }
    }

    public enum Slot: Sendable {
        case initial, medial, final
    }

    /// The symbol each key types on the standard layout, by the key's
    /// character on a US keyboard.
    public static let keyboard: [Character: Character] = [
        "1": "ㄅ", "q": "ㄆ", "a": "ㄇ", "z": "ㄈ",
        "2": "ㄉ", "w": "ㄊ", "s": "ㄋ", "x": "ㄌ",
        "e": "ㄍ", "d": "ㄎ", "c": "ㄏ",
        "r": "ㄐ", "f": "ㄑ", "v": "ㄒ",
        "5": "ㄓ", "t": "ㄔ", "g": "ㄕ", "b": "ㄖ",
        "y": "ㄗ", "h": "ㄘ", "n": "ㄙ",
        "u": "ㄧ", "j": "ㄨ", "m": "ㄩ",
        "8": "ㄚ", "i": "ㄛ", "k": "ㄜ", ",": "ㄝ",
        "9": "ㄞ", "o": "ㄟ", "l": "ㄠ", ".": "ㄡ",
        "0": "ㄢ", "p": "ㄣ", ";": "ㄤ", "/": "ㄥ", "-": "ㄦ",
    ]

    /// Keys that end a syllable with its tone.
    public static let toneKeys: [Character: Tone] = [" ": .first, "6": .second, "3": .third, "4": .fourth, "7": .neutral]

    private static let initials: [Character: String] = [
        "ㄅ": "b", "ㄆ": "p", "ㄇ": "m", "ㄈ": "f", "ㄉ": "d", "ㄊ": "t", "ㄋ": "n", "ㄌ": "l",
        "ㄍ": "g", "ㄎ": "k", "ㄏ": "h", "ㄐ": "j", "ㄑ": "q", "ㄒ": "x",
        "ㄓ": "zh", "ㄔ": "ch", "ㄕ": "sh", "ㄖ": "r", "ㄗ": "z", "ㄘ": "c", "ㄙ": "s",
    ]
    private static let medials: Set<Character> = ["ㄧ", "ㄨ", "ㄩ"]
    private static let finals: [Character: String] = [
        "ㄚ": "a", "ㄛ": "o", "ㄜ": "e", "ㄝ": "e", "ㄞ": "ai", "ㄟ": "ei", "ㄠ": "ao", "ㄡ": "ou",
        "ㄢ": "an", "ㄣ": "en", "ㄤ": "ang", "ㄥ": "eng", "ㄦ": "er",
    ]

    public static func slot(of symbol: Character) -> Slot? {
        if initials[symbol] != nil { return .initial }
        if medials.contains(symbol) { return .medial }
        if finals[symbol] != nil { return .final }
        return nil
    }

    /// One syllable's symbols, at most one per slot, and its tone once
    /// typed.
    public struct Syllable: Hashable, Sendable {
        public var initial: Character?
        public var medial: Character?
        public var final: Character?
        public var tone: Tone?

        public init(initial: Character? = nil, medial: Character? = nil, final: Character? = nil, tone: Tone? = nil) {
            self.initial = initial
            self.medial = medial
            self.final = final
            self.tone = tone
        }

        /// Reads symbols and an optional tone mark, such as `ㄋㄧˇ` or `˙ㄉㄜ`.
        public init?(_ text: some StringProtocol) {
            for character in text {
                if let tone = Tone.allCases.first(where: { $0.mark == character }) {
                    guard self.tone == nil else { return nil }
                    self.tone = tone
                    continue
                }
                switch Zhuyin.slot(of: character) {
                case .initial?: guard initial == nil else { return nil }; initial = character
                case .medial?: guard medial == nil else { return nil }; medial = character
                case .final?: guard final == nil else { return nil }; final = character
                case nil: return nil
                }
            }
            guard !isEmpty else { return nil }
            if tone == nil { tone = .first }
        }

        public var isEmpty: Bool { initial == nil && medial == nil && final == nil }

        /// Places `symbol` in its slot, replacing what was there, as the
        /// standard layout's input methods do.
        public mutating func type(_ symbol: Character) {
            switch Zhuyin.slot(of: symbol) {
            case .initial?: initial = symbol
            case .medial?: medial = symbol
            case .final?: final = symbol
            case nil: break
            }
        }

        /// Removes the last symbol in slot order.
        public mutating func deleteLast() {
            if final != nil { final = nil } else if medial != nil { medial = nil } else { initial = nil }
        }

        /// The symbols in order, without the tone.
        public var symbols: String { String([initial, medial, final].compactMap { $0 }) }

        /// As written: the symbols, the tone's mark after them, or the
        /// neutral dot before.
        public var text: String {
            switch tone {
            case .neutral?: "˙" + symbols
            case let tone?: symbols + (tone.mark.map(String.init) ?? "")
            case nil: symbols
            }
        }

        /// The toneless pinyin, with ü written v (`nv`, `lve`); nil when the
        /// symbols spell no syllable.
        public var pinyin: String? {
            Zhuyin.pinyin(initial: initial, medial: medial, final: final)
        }

        /// What librime reads for the syllable: pinyin then the tone's
        /// digit (`ni3`, `de5`).
        public var code: String? {
            guard let pinyin, let tone else { return nil }
            return pinyin + String(tone.rawValue)
        }
    }

    // MARK: Pinyin

    private static func pinyin(initial: Character?, medial: Character?, final: Character?) -> String? {
        let finalPinyin = final.flatMap { finals[$0] }
        guard let initial else {
            switch medial {
            case nil:
                // ㄝ alone is ê, which the dictionary does not write.
                guard let finalPinyin, final != "ㄝ" else { return nil }
                return finalPinyin
            case "ㄧ"?:
                guard let final else { return "yi" }
                return ["ㄚ": "ya", "ㄛ": "yo", "ㄝ": "ye", "ㄞ": "yai", "ㄠ": "yao", "ㄡ": "you",
                        "ㄢ": "yan", "ㄣ": "yin", "ㄤ": "yang", "ㄥ": "ying"][final]
            case "ㄨ"?:
                guard final != nil else { return "wu" }
                return ["ㄚ": "wa", "ㄛ": "wo", "ㄞ": "wai", "ㄟ": "wei", "ㄢ": "wan", "ㄣ": "wen", "ㄤ": "wang", "ㄥ": "weng"][final!]
            case "ㄩ"?:
                guard final != nil else { return "yu" }
                return ["ㄝ": "yue", "ㄢ": "yuan", "ㄣ": "yun", "ㄥ": "yong"][final!]
            default:
                return nil
            }
        }
        guard let start = initials[initial] else { return nil }
        // ㄐ ㄑ ㄒ take only ㄧ and ㄩ; ㄓ through ㄙ never take ㄧ or ㄩ.
        let palatal = "ㄐㄑㄒ".contains(initial)
        if palatal, medial != "ㄧ", medial != "ㄩ" { return nil }
        if "ㄓㄔㄕㄖㄗㄘㄙ".contains(initial), medial == "ㄧ" || medial == "ㄩ" { return nil }
        switch medial {
        case nil:
            guard let finalPinyin else {
                // ㄓ ㄔ ㄕ ㄖ ㄗ ㄘ ㄙ alone carry the empty rhyme, written i.
                return "ㄓㄔㄕㄖㄗㄘㄙ".contains(initial) ? start + "i" : nil
            }
            // ㄝ follows only ㄧ and ㄩ; ㄜ is the e of de and ge.
            return final == "ㄝ" ? nil : start + finalPinyin
        case "ㄧ"?:
            guard final != nil else { return start + "i" }
            guard let rest = ["ㄚ": "ia", "ㄛ": "io", "ㄝ": "ie", "ㄞ": "iai", "ㄠ": "iao", "ㄡ": "iu",
                              "ㄢ": "ian", "ㄣ": "in", "ㄤ": "iang", "ㄥ": "ing"][final!] else { return nil }
            return start + rest
        case "ㄨ"?:
            guard final != nil else { return start + "u" }
            guard let rest = ["ㄚ": "ua", "ㄛ": "uo", "ㄞ": "uai", "ㄟ": "ui", "ㄢ": "uan", "ㄣ": "un", "ㄤ": "uang", "ㄥ": "ong"][final!] else { return nil }
            return start + rest
        case "ㄩ"?:
            guard palatal || "ㄋㄌ".contains(initial) else { return nil }
            guard final != nil else { return start + (palatal ? "u" : "v") }
            let rest: [Character: String] = palatal
                ? ["ㄝ": "ue", "ㄢ": "uan", "ㄣ": "un", "ㄥ": "iong"]
                : ["ㄝ": "ve"]
            return rest[final!].map { start + $0 }
        default:
            return nil
        }
    }

    /// The syllable that pinyin (toneless, ü as v) is written as, for the
    /// syllables of `syllabary`.
    public static func syllables(of syllabary: some Sequence<String>) -> [String: Syllable] {
        var byPinyin: [String: Syllable] = [:]
        let slots: [Character?] = [nil] + Array(initials.keys)
        for initial in slots {
            for medial in [nil] + Array(medials) as [Character?] {
                for final in [nil] + Array(finals.keys) as [Character?] {
                    let syllable = Syllable(initial: initial, medial: medial, final: final)
                    guard !syllable.isEmpty, let pinyin = syllable.pinyin else { continue }
                    byPinyin[pinyin] = syllable
                }
            }
        }
        let known = Set(syllabary)
        return byPinyin.filter { known.contains($0.key) }
    }

    /// The code librime reads for a tone-marked pinyin syllable of the
    /// dictionary (`nǐ` → `ni3`, `de` → `de5`), as the schema's `tones`
    /// rules write it.
    public static func code(ofTonedPinyin syllable: String) -> String {
        var letters = ""
        var tone = Tone.neutral
        for character in syllable {
            if let (base, marked) = toneMarks[character] {
                letters.append(base)
                tone = marked
            } else {
                letters.append(character == "ü" ? "v" : character)
            }
        }
        return letters + String(tone.rawValue)
    }

    private static let toneMarks: [Character: (Character, Tone)] = {
        var marks: [Character: (Character, Tone)] = [:]
        let rows: [(Character, String)] = [("a", "āáǎà"), ("o", "ōóǒò"), ("e", "ēéěè"), ("i", "īíǐì"), ("u", "ūúǔù"), ("v", "ǖǘǚǜ")]
        for (base, marked) in rows {
            for (index, character) in marked.enumerated() { marks[character] = (base, Tone(rawValue: index + 1)!) }
        }
        marks["ń"] = ("n", .second)
        marks["ň"] = ("n", .third)
        marks["ǹ"] = ("n", .fourth)
        marks["ḿ"] = ("m", .second)
        marks["m\u{300}"] = ("m", .fourth)
        return marks
    }()

    /// librime spelling rules that rewrite the dictionary's tone-marked
    /// syllables as `code(ofTonedPinyin:)` does: each marked vowel becomes
    /// its letter and the tone's digit, the digit moves to the end, and a
    /// syllable without a mark takes the neutral tone.
    public static let toneRules: [String] = {
        var rules: [String] = []
        for (character, (base, tone)) in toneMarks.sorted(by: { $0.key < $1.key }) {
            rules.append("xform/\(character)/\(base)\(tone.rawValue)/")
        }
        rules.append("xlit/ü/v/")
        rules.append("xform/^([a-z]*)([1-4])([a-z]*)$/$1$3$2/")
        rules.append("xform/^([a-z]+)$/$1_/")
        rules.append("xform/_$/5/")
        return rules
    }()
}
