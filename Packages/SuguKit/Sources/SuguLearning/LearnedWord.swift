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
