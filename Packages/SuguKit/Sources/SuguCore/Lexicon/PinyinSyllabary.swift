import Foundation

/// Toneless pinyin syllables, for splitting letters into them.
public struct PinyinSyllabary: Sendable {
    private let syllables: Set<String>
    private let longest: Int

    /// The interjection syllables without a vowel (m, n, ng) are left out:
    /// words are not written with them, and they would make `xian` split
    /// as `xia n` as well as `xi an`.
    public init(_ syllables: Set<String>) {
        self.syllables = syllables.filter { $0.contains(where: "aeiouv".contains) }
        longest = self.syllables.map(\.count).max() ?? 0
    }

    /// The ways `letters` splits into exactly `count` syllables, each as
    /// the offsets where its second and later syllables begin; at most
    /// `limit`.
    public func splits(of letters: String, count: Int, limit: Int = 2) -> [[Int]] {
        let letters = Array(letters)
        var results: [[Int]] = []
        var starts: [Int] = []
        func search(_ position: Int) {
            guard results.count < limit else { return }
            if position == letters.count {
                if starts.count == count - 1 { results.append(starts) }
                return
            }
            guard starts.count < count else { return }
            for end in (position + 1)...min(letters.count, position + longest)
            where syllables.contains(String(letters[position..<end])) {
                if end < letters.count { starts.append(end) }
                search(end)
                if end < letters.count { starts.removeLast() }
            }
        }
        if count > 0, !letters.isEmpty, longest > 0 { search(0) }
        return results
    }
}
