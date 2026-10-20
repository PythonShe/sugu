/// Decides when typed letters in Chinese mode are meant as Latin text
/// (`github`, `v2`) rather than pinyin.
public struct LatinInference: Sendable {
    /// Toneless pinyin syllables (`v` for ü). Loaded from the bundled
    /// dictionary data, not hard-coded.
    public let syllables: Set<String>
    /// Common English words, lowercased.
    public let englishWords: Set<String>
    /// Strings the user always wants as Latin, even when they parse as
    /// pinyin abbreviations (`nb`, `yyds`).
    public var allowList: Set<String>

    private let longestSyllable: Int
    private let syllablePrefixes: Set<String>

    public init(syllables: Set<String>, englishWords: Set<String> = [], allowList: Set<String> = []) {
        self.syllables = syllables
        self.englishWords = englishWords
        self.allowList = allowList
        self.longestSyllable = syllables.map(\.count).max() ?? 0
        var prefixes = Set<String>()
        for syllable in syllables {
            for length in 1...syllable.count {
                prefixes.insert(String(syllable.prefix(length)))
            }
        }
        self.syllablePrefixes = prefixes
    }

    public enum Placement: Sendable, Equatable {
        /// Offer the Latin text as the first candidate.
        case first
        /// Offer it after the engine's candidates.
        case last
    }

    public func placement(for input: String) -> Placement {
        let lowered = input.lowercased()
        if allowList.contains(lowered) { return .first }
        if input.contains(where: { !$0.isASCIILetter && $0 != "'" }) { return .first }
        if input.contains(where: \.isUppercase) { return .first }
        if !isPinyin(lowered) { return .first }
        if englishWords.contains(lowered), lowered.count >= 4, !isFullSyllables(lowered) { return .first }
        return .last
    }

    /// Whether typed letters are a known English word or on the allow list,
    /// for offering them as typed in Japanese mode.
    public func isEnglishWord(_ input: String) -> Bool {
        let lowered = input.lowercased()
        return allowList.contains(lowered) || (lowered.count >= 3 && englishWords.contains(lowered))
    }

    /// Whether the input splits into syllables, allowing the last one to be
    /// incomplete and apostrophes as separators.
    public func isPinyin(_ input: String) -> Bool {
        segments(Array(input), allowPartialTail: true)
    }

    /// Whether the input splits into complete syllables only.
    public func isFullSyllables(_ input: String) -> Bool {
        segments(Array(input), allowPartialTail: false)
    }

    private func segments(_ chars: [Character], allowPartialTail: Bool) -> Bool {
        guard !syllables.isEmpty else { return true }
        // reachable[i]: chars[..<i] splits into whole syllables.
        var reachable = Array(repeating: false, count: chars.count + 1)
        reachable[0] = true
        for start in 0..<chars.count where reachable[start] {
            if chars[start] == "'" {
                reachable[start + 1] = true
                continue
            }
            var piece = ""
            for end in start..<min(chars.count, start + longestSyllable) {
                if chars[end] == "'" { break }
                piece.append(chars[end])
                if syllables.contains(piece) { reachable[end + 1] = true }
                if allowPartialTail, end == chars.count - 1, syllablePrefixes.contains(piece) {
                    return true
                }
                if !syllablePrefixes.contains(piece) { break }
            }
        }
        return reachable[chars.count]
    }
}
