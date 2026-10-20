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
    public var text: String
    public var kind: Kind
    public var count: Int
    public var pinned: Bool
    public var firstUsed: Date
    public var lastUsed: Date

    public init(id: Int64, mode: InputMode, reading: String, text: String, kind: Kind, count: Int, pinned: Bool, firstUsed: Date, lastUsed: Date) {
        self.id = id
        self.mode = mode
        self.reading = reading
        self.text = text
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

    /// The key words are stored and looked up under: case- and
    /// separator-insensitive pinyin, or hiragana.
    public static func normalize(_ reading: String, mode: InputMode) -> String {
        switch mode {
        case .chinese:
            reading.lowercased().filter { $0 != "'" && $0 != " " }
        case .japanese:
            WidthConversion.hiragana(reading).filter { $0 != " " && $0 != "　" }
        case .english:
            reading.lowercased()
        }
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
