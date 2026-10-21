import Foundation
import SuguCore

/// A word Sugu knows beyond the engines' dictionaries: learned from the
/// user's commits, or added by the user.
public struct LearnedWord: Sendable, Hashable, Identifiable {
    public enum Kind: Int, Sendable, Codable {
        /// Learned from commits; expires when unused.
        case learned = 0
        /// Added by the user or imported; never expires.
        case user = 1
    }

    public var id: Int64
    public var mode: InputMode
    public var reading: String
    /// The word as stored and matched: Chinese in Simplified, whatever
    /// script it was typed in, so one word is one entry (D-094).
    public var text: String
    /// The word as last typed, in `script`; `text` for Japanese.
    public var shown: String
    /// The script `shown` is in; nil for Japanese, and for Chinese words
    /// from a file that does not say.
    public var script: ChineseScript?
    public var kind: Kind
    public var count: Int
    public var pinned: Bool
    public var firstUsed: Date
    public var lastUsed: Date

    public init(id: Int64, mode: InputMode, reading: String, text: String, kind: Kind, count: Int, pinned: Bool, firstUsed: Date, lastUsed: Date,
                shown: String? = nil, script: ChineseScript? = nil) {
        self.id = id
        self.mode = mode
        self.reading = reading
        self.text = text
        self.shown = shown ?? text
        self.script = script
        self.kind = kind
        self.count = count
        self.pinned = pinned
        self.firstUsed = firstUsed
        self.lastUsed = lastUsed
    }

    /// Ranking among words with the same reading: pinned first, then user
    /// words, then by use with a decay of about a month.
    public func score(at now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(lastUsed) / 86_400)
        let usage = log2(Double(count) + 1) * exp(-days / 30)
        return (pinned ? 1_000 : 0) + (kind == .user ? 100 : 0) + usage
    }

    /// Whether the word goes before the engine's own first choice: one the
    /// user pinned, added, or chose more than once. A word chosen once
    /// follows it, so one stray choice does not take over the reading.
    public var isEstablished: Bool {
        pinned || kind == .user || count >= 2
    }

    /// The key words are stored and looked up under: case-insensitive
    /// pinyin without spaces, or hiragana.
    ///
    /// An apostrophe the user typed stays where pinyin needs one, before a
    /// syllable starting with a, o or e (xi'an, not xian) or between n and g
    /// (fan'gan, not fang'an), so a word picked for `xi'an` is not offered
    /// first for `xian`. Elsewhere it marks a boundary the keys already
    /// make (ni'hao) and is dropped.
    public static func normalize(_ reading: String, mode: InputMode) -> String {
        switch mode {
        case .chinese:
            let letters = Array(reading.lowercased().filter { $0 != " " })
            var result = ""
            for (index, character) in letters.enumerated() {
                guard character == "'" else { result.append(character); continue }
                guard let previous = result.last, previous != "'", index + 1 < letters.count else { continue }
                let next = letters[index + 1]
                if "aoe".contains(next) || (previous == "n" && next == "g") { result.append(character) }
            }
            return result
        case .japanese:
            return WidthConversion.hiragana(reading).filter { $0 != " " && $0 != "　" }
        case .english:
            return reading.lowercased()
        }
    }

    /// The key for a reading the user did not type into a composition (an
    /// added or imported word): import formats separate every syllable,
    /// so no apostrophe is kept.
    public static func normalize(enteredReading reading: String, mode: InputMode) -> String {
        normalize(mode == .chinese ? reading.filter { $0 != "'" } : reading, mode: mode)
    }
}

/// A word the user deleted. Kept for sync, so older copies on other Macs
/// are deleted too and an older copy coming back is refused.
public struct WordDeletion: Sendable, Hashable {
    public var mode: InputMode
    public var reading: String
    public var text: String
    public var kind: LearnedWord.Kind
    public var deletedAt: Date

    public init(mode: InputMode, reading: String, text: String, kind: LearnedWord.Kind, deletedAt: Date) {
        self.mode = mode
        self.reading = reading
        self.text = text
        self.kind = kind
        self.deletedAt = deletedAt
    }
}
