import Foundation

/// Katakana for foreign words typed in Latin letters, in Japanese mode: the
/// bundled dictionary, the optional larger one, and guesses for the rest.
public final class ForeignWords: Sendable {
    /// What is known about typed letters.
    public struct Match: Sendable, Equatable {
        /// The letters as stored, which words chosen are learned under.
        public var spelling: String
        /// From the dictionaries, best first.
        public var words: [String]
        /// The spelling is also the romaji of a native Japanese word.
        public var alsoJapanese: Bool
        /// Guesses, best first; only when no dictionary has the spelling and
        /// the letters do not read as romaji.
        public var guesses: [String]
    }

    public static let bundledDictionaryFile = "loanwords.bin"
    public static let guesserFile = "katakana-guesser.bin"
    /// Guesses are for words, not stray fragments of a Japanese word.
    static let minimumGuessLength = 4
    static let guessLimit = 5

    private let tables: [LoanwordTable]
    private let guesser: KatakanaGuesser?

    public init(tables: [LoanwordTable], guesser: KatakanaGuesser?) {
        self.tables = tables
        self.guesser = guesser
    }

    /// Loads the bundled data and, when present, the downloaded dictionary;
    /// nil when there is nothing to offer.
    public convenience init?(lexicon: URL, download: URL? = nil) {
        var tables: [LoanwordTable] = []
        if let bundled = try? LoanwordTable(contentsOf: lexicon.appendingPathComponent(Self.bundledDictionaryFile)) { tables.append(bundled) }
        if let download, let extra = try? LoanwordTable(contentsOf: download) { tables.append(extra) }
        let guesser = try? KatakanaGuesser(contentsOf: lexicon.appendingPathComponent(Self.guesserFile))
        guard !tables.isEmpty || guesser != nil else { return nil }
        self.init(tables: tables, guesser: guesser)
    }

    /// The match for what was typed, with nothing in it when the spelling is
    /// unknown; nil when it could not be a spelling at all (kana keys,
    /// symbols).
    public func match(typed: String) -> Match? {
        guard let key = LoanwordSpelling.key(typed) else { return nil }
        var words: [String] = []
        var alsoJapanese = false
        for table in tables {
            guard let entry = table.entry(for: key) else { continue }
            alsoJapanese = alsoJapanese || entry.alsoJapanese
            for word in entry.words where !words.contains(word) { words.append(word) }
        }
        var guesses: [String] = []
        if words.isEmpty, key.count >= Self.minimumGuessLength, let guesser, RomajiReading(key).looksForeign {
            guesses = guesser.guesses(for: key, limit: Self.guessLimit).map(\.text)
        }
        return Match(spelling: key, words: words, alsoJapanese: alsoJapanese, guesses: guesses)
    }
}
