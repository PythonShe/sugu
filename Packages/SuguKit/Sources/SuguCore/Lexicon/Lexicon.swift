import Foundation

/// Word lists extracted from the bundled dictionary data at build time:
/// one entry per line.
public enum Lexicon {
    public static let syllablesFile = "pinyin-syllables.txt"
    public static let englishWordsFile = "english-words.txt"

    public static func load(_ name: String, in directory: URL) -> Set<String> {
        guard let text = try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8) else { return [] }
        return Set(text.split(whereSeparator: \.isNewline).map(String.init))
    }

    /// Toneless syllables from a Rime dictionary's reading column.
    public static func syllables(fromRimeDictionary text: String) -> Set<String> {
        var result = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count >= 2 else { continue }
            for syllable in columns[1].split(separator: " ") {
                // ü decomposes to u + U+0308 and is written v; other marks are
                // tones. Work on scalars: a toned ü (ǚ) is one grapheme, so a
                // string search for "ü" would not match it.
                var scalars = String.UnicodeScalarView()
                for scalar in syllable.decomposedStringWithCanonicalMapping.unicodeScalars {
                    if scalar.value == 0x0308, scalars.last == "u" {
                        scalars.removeLast()
                        scalars.append("v")
                    } else if !(0x0300...0x036F).contains(scalar.value) {
                        scalars.append(scalar)
                    }
                }
                let plain = String(scalars)
                if !plain.isEmpty, plain.allSatisfy(\.isASCIILowercaseLetter) {
                    result.insert(plain)
                }
            }
        }
        return result
    }

    /// The most frequent lowercase English words from a Rime English
    /// dictionary (word, code, weight).
    public static func englishWords(fromRimeDictionary text: String, limit: Int) -> [String] {
        var weighted: [(String, Int)] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let columns = line.split(separator: "\t")
            guard columns.count >= 3, let weight = Int(columns[2]) else { continue }
            let word = String(columns[0])
            guard word.count >= 2, word.allSatisfy(\.isASCIILowercaseLetter) else { continue }
            weighted.append((word, weight))
        }
        weighted.sort { $0.1 > $1.1 }
        var seen = Set<String>()
        var words: [String] = []
        for (word, _) in weighted where words.count < limit && seen.insert(word).inserted {
            words.append(word)
        }
        return words
    }
}
