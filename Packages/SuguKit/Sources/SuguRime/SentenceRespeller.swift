import Foundation
import SuguCore
import SuguLM

/// Chinese words by their toneless syllables, read from
/// `Lexicon.pinyinWordsFile` (word, syllables, weight per line). Keys are
/// 64-bit hashes and the kept spellings one flat array: as strings, the
/// list's 120 thousand words would take 45 MB.
public struct PinyinWords: Sendable {
    struct Spelling: Sendable {
        var text: String
        var logProbability: Float
    }

    /// Each word's log probability, by its text and reading.
    private let words: [UInt64: Float]
    /// The likeliest spellings of each reading, at most
    /// `spellingsPerReading`, as a range of `spellingList`.
    private let spellingRanges: [UInt64: Range<Int32>]
    private let spellingList: [Spelling]
    static let spellingsPerReading = 6

    /// Reads lines grouped by syllables, heaviest first, as
    /// `Lexicon.pinyinWords` writes them.
    public init(data: Data) {
        var words: [UInt64: Float] = [:]
        var ranges: [UInt64: Range<Int32>] = [:]
        var list: [Spelling] = []
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            // Each line's word, reading, and weight; nil for a malformed line.
            func forEachLine(_ body: (Range<Int>, Range<Int>, Double) -> Void) {
                var start = 0
                while start < bytes.count {
                    let lineEnd = bytes[start...].firstIndex(of: 0x0A) ?? bytes.count
                    defer { start = lineEnd + 1 }
                    let end = lineEnd > start && bytes[lineEnd - 1] == 0x0D ? lineEnd - 1 : lineEnd
                    guard let firstTab = bytes[start..<end].firstIndex(of: 0x09),
                          let secondTab = bytes[(firstTab + 1)..<end].firstIndex(of: 0x09),
                          let weight = Double(String(decoding: bytes[(secondTab + 1)..<end], as: UTF8.self)), weight > 0
                    else { continue }
                    body(start..<firstTab, (firstTab + 1)..<secondTab, weight)
                }
            }
            var total = 0.0
            var count = 0
            var readings = 0
            var spellings = 0
            var previous: (reading: UInt64, count: Int)?
            forEachLine { _, reading, weight in
                total += weight
                count += 1
                var key = WordKey()
                key.add(bytes[reading])
                let inGroup = previous.flatMap { $0.reading == key.value ? $0.count + 1 : nil } ?? 1
                if inGroup == 1 { readings += 1 }
                if inGroup <= Self.spellingsPerReading { spellings += 1 }
                previous = (key.value, inGroup)
            }
            words.reserveCapacity(count)
            ranges.reserveCapacity(readings)
            list.reserveCapacity(spellings)
            var group: (reading: UInt64, first: Int32)?
            forEachLine { word, reading, weight in
                let logProbability = Float(log(weight / total))
                var readingKey = WordKey()
                readingKey.add(bytes[reading])
                var wordKey = WordKey()
                wordKey.add(bytes[word])
                wordKey.add(CollectionOfOne(0x09))
                wordKey.add(bytes[reading])
                words[wordKey.value] = logProbability
                if group?.reading != readingKey.value {
                    if let group { ranges[group.reading] = group.first..<Int32(list.count) }
                    group = (readingKey.value, Int32(list.count))
                }
                if let group, list.count - Int(group.first) < Self.spellingsPerReading {
                    list.append(Spelling(text: String(decoding: bytes[word], as: UTF8.self), logProbability: logProbability))
                }
            }
            if let group { ranges[group.reading] = group.first..<Int32(list.count) }
        }
        self.words = words
        spellingRanges = ranges
        spellingList = list
    }

    public init(lines: [String]) {
        self.init(data: Data(lines.joined(separator: "\n").utf8))
    }

    public init(contentsOf url: URL) throws {
        self.init(data: try Data(contentsOf: url, options: .mappedIfSafe))
    }

    /// The log probability of the word `text` read as `syllables`, nil when
    /// the list does not have it.
    func logProbability(of text: some StringProtocol, readAs syllables: ArraySlice<String>) -> Float? {
        var key = WordKey()
        key.add(text.utf8)
        key.add(CollectionOfOne(0x09))
        key.add(syllables)
        return words[key.value]
    }

    /// The likeliest words read as `syllables`.
    func spellings(of syllables: ArraySlice<String>) -> ArraySlice<Spelling> {
        var key = WordKey()
        key.add(syllables)
        guard let range = spellingRanges[key.value] else { return [] }
        return spellingList[Int(range.lowerBound)..<Int(range.upperBound)]
    }
}

/// FNV-1a over UTF-8, for the keys of `PinyinWords` and the respeller's
/// caches; at 64 bits, two of a few hundred thousand keys colliding is a
/// chance of about one in a billion.
struct WordKey {
    private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

    mutating func add(_ bytes: some Sequence<UInt8>) {
        for byte in bytes { value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
    }

    /// Syllables separated by spaces, as the word list writes a reading.
    mutating func add(_ syllables: ArraySlice<String>) {
        for (offset, syllable) in syllables.enumerated() {
            if offset > 0 { add(CollectionOfOne(0x20)) }
            add(syllable.utf8)
        }
    }
}

/// Rewrites librime's sentence where the character language model reads
/// another spelling of the same syllables as clearly more natural (ADR
/// 0005, decision 8): 吃完饭 for 吃晚饭 is one word away from librime's
/// choice, and librime offers no other whole sentence to choose from.
@MainActor
public final class SentenceRespeller {
    let model: CharacterLanguageModel
    let words: PinyinWords
    /// Weight of the word list's probabilities against the model's.
    static let dictionaryWeight: Float = 0.3
    /// How much more natural a respelling must read, in natural log
    /// probability, before it replaces librime's words.
    static let margin: Float = 4
    /// Syllables in the longest span respelled at once.
    static let longestSpan = 3
    private static let enumerationLimit = 400
    private static let cacheLimit = 50_000
    /// Up to `enumerationLimit` spellings each.
    private static let spellingCacheLimit = 2_048

    /// Log probabilities of text in context, kept across keystrokes: most
    /// of a sentence is the same as at the keystroke before.
    private var scores: [UInt64: Float] = [:]
    private var spellingCache: [UInt64: [PinyinWords.Spelling]] = [:]
    /// Texts of the user's learned words; characters inside one keep their
    /// spelling.
    public var userWords: Set<String> = [] {
        didSet { longestUserWord = userWords.map(\.count).max() ?? 0 }
    }
    private var longestUserWord = 0

    public init(model: CharacterLanguageModel, words: PinyinWords) {
        self.model = model
        self.words = words
    }

    private struct Piece {
        var text: String
        var syllables: [String]
        var logProbability: Float
    }

    /// `text` respelled, or nil when it reads best as it is or cannot be
    /// read as words of the list for any of `readings` (syllables for each
    /// of its characters, likeliest first).
    public func respelled(_ text: String, readings: [[String]], after history: String) -> String? {
        let characters = Array(text)
        guard let pieces = readings.lazy.compactMap({ self.segment(characters, $0) }).first else { return nil }
        let kept = userWordCharacters(in: characters)
        let history = String(history.suffix(model.order - 1))
        var result = pieces
        var index = 0
        while index < result.count {
            let start = result[..<index].map(\.text.count).reduce(0, +)
            for span in stride(from: min(3, result.count - index), through: 1, by: -1) {
                let original = result[index..<(index + span)]
                let syllables = original.flatMap(\.syllables)
                let text = original.map(\.text).joined()
                guard syllables.count <= Self.longestSpan, !kept.intersects(integersIn: start..<(start + text.count)) else { continue }
                let before = history + result[..<index].map(\.text).joined()
                let after = String(result[(index + span)...].map(\.text).joined().prefix(model.order - 1))
                let base = original.map(\.logProbability).reduce(0, +)
                let threshold = score(text, between: before, and: after) + Self.margin
                var choice: (spelling: PinyinWords.Spelling, score: Float)?
                for spelling in spellings(of: syllables) where spelling.text != text {
                    let trial = score(spelling.text, between: before, and: after) + Self.dictionaryWeight * (spelling.logProbability - base)
                    if trial > choice?.score ?? threshold { choice = (spelling, trial) }
                }
                if let choice {
                    result.replaceSubrange(index..<(index + span), with: [Piece(text: choice.spelling.text, syllables: syllables, logProbability: choice.spelling.logProbability)])
                    break
                }
            }
            index += 1
        }
        let respelled = result.map(\.text).joined()
        return respelled == text ? nil : respelled
    }

    /// The likeliest split of `characters` into listed words read as
    /// `syllables`, one syllable per character.
    private func segment(_ characters: [Character], _ syllables: [String]) -> [Piece]? {
        guard characters.count == syllables.count, !characters.isEmpty else { return nil }
        var best = [(score: Float, length: Int)?](repeating: nil, count: characters.count + 1)
        best[characters.count] = (0, 0)
        for start in stride(from: characters.count - 1, through: 0, by: -1) {
            for length in 1...min(Self.longestSpan, characters.count - start) {
                guard let rest = best[start + length],
                      let probability = words.logProbability(of: String(characters[start..<(start + length)]), readAs: syllables[start..<(start + length)])
                else { continue }
                if probability + rest.score > best[start]?.score ?? -.infinity { best[start] = (probability + rest.score, length) }
            }
        }
        var pieces: [Piece] = []
        var start = 0
        while start < characters.count {
            guard let step = best[start] else { return nil }
            let end = start + step.length
            let text = String(characters[start..<end])
            pieces.append(Piece(text: text, syllables: Array(syllables[start..<end]), logProbability: words.logProbability(of: text, readAs: syllables[start..<end]) ?? 0))
            start = end
        }
        return pieces
    }

    /// Ways to write `syllables` as one or more listed words, with the sum
    /// of their log probabilities.
    private func spellings(of syllables: [String]) -> [PinyinWords.Spelling] {
        var hasher = WordKey()
        hasher.add(syllables[...])
        let key = hasher.value
        if let known = spellingCache[key] { return known }
        var found: [PinyinWords.Spelling] = []
        func extend(_ position: Int, _ text: String, _ logProbability: Float) {
            guard found.count < Self.enumerationLimit else { return }
            if position == syllables.count {
                found.append(.init(text: text, logProbability: logProbability))
                return
            }
            for length in 1...(syllables.count - position) {
                for spelling in words.spellings(of: syllables[position..<(position + length)]) {
                    extend(position + length, text + spelling.text, logProbability + spelling.logProbability)
                }
            }
        }
        extend(0, "", 0)
        if spellingCache.count >= Self.spellingCacheLimit { spellingCache = [:] }
        spellingCache[key] = found
        return found
    }

    /// The model's log probability of `text` and the characters after it
    /// that it conditions, after `before`; a short `before` is the start of
    /// the text, as when the whole sentence is scored.
    private func score(_ text: String, between before: String, and after: String) -> Float {
        let start = String(repeating: Self.start, count: max(0, model.order - 1 - before.count))
        let context = start + before.suffix(model.order - 1)
        var hasher = WordKey()
        for part in [context, text, after] {
            hasher.add(part.utf8)
            hasher.add(CollectionOfOne(0x1F))
        }
        let key = hasher.value
        if let known = scores[key] { return known }
        let value = model.logProbability(of: text + after, after: context)
        if scores.count >= Self.cacheLimit { scores = [:] }
        scores[key] = value
        return value
    }

    /// The language model's start-of-text marker.
    private static let start: Character = "\u{2}"

    /// Offsets of characters inside a user word that `characters` contains.
    private func userWordCharacters(in characters: [Character]) -> IndexSet {
        var kept = IndexSet()
        guard longestUserWord > 0 else { return kept }
        for start in characters.indices {
            for end in (start + 1)...min(characters.count, start + longestUserWord) where userWords.contains(String(characters[start..<end])) {
                kept.insert(integersIn: start..<end)
            }
        }
        return kept
    }
}
