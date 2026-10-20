import Foundation
import SuguCore

/// Readings of Chinese text, for reconverting text Sugu did not type: the
/// text split into listed words so their weights are likeliest, read from
/// `Lexicon.pinyinWordsFile` (word, syllables, weight per line). Only the
/// lines of words in the text are kept, so nothing stays in memory.
public enum ChineseReadings {
    /// The toneless syllables of Simplified `text`, one per character; nil
    /// when a character is in no listed word.
    public static func syllables(of text: String, wordList: Data) -> [String]? {
        let characters = Array(text)
        guard !characters.isEmpty else { return nil }
        // The likeliest reading of each listed word found in the text. Lines
        // are read as bytes; only words starting with a character of the
        // text become strings.
        let firsts = Set(characters.map { Array(String($0).utf8) })
        var found: [String: (syllables: [String], weight: Double)] = [:]
        var total = 0.0
        wordList.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let tab = UInt8(ascii: "\t"), newline = UInt8(ascii: "\n")
            var start = 0
            while start < bytes.count {
                var end = start
                while end < bytes.count, bytes[end] != newline { end += 1 }
                defer { start = end + 1 }
                guard let firstTab = (start..<end).first(where: { bytes[$0] == tab }),
                      let secondTab = (firstTab + 1..<end).first(where: { bytes[$0] == tab }) else { continue }
                var weight = 0.0
                for index in secondTab + 1..<end {
                    let digit = bytes[index] &- UInt8(ascii: "0")
                    guard digit < 10 else { break }
                    weight = weight * 10 + Double(digit)
                }
                total += weight
                // The first character's bytes: up to 4 in UTF-8.
                let lead = bytes[start]
                let length = lead < 0x80 ? 1 : lead < 0xE0 ? 2 : lead < 0xF0 ? 3 : 4
                guard start + length <= firstTab, firsts.contains(Array(bytes[start..<start + length])) else { continue }
                let word = String(decoding: bytes[start..<firstTab], as: UTF8.self)
                guard text.contains(word), weight > found[word]?.weight ?? 0 else { continue }
                let syllables = String(decoding: bytes[firstTab + 1..<secondTab], as: UTF8.self).split(separator: " ").map(String.init)
                guard syllables.count == word.count else { continue }
                found[word] = (syllables, weight)
            }
        }
        guard total > 0 else { return nil }
        let longest = found.keys.map(\.count).max() ?? 0
        // best[i]: the likeliest split of the first i characters.
        var best: [(score: Double, syllables: [String])?] = Array(repeating: nil, count: characters.count + 1)
        best[0] = (0, [])
        for end in 1...characters.count {
            for start in max(0, end - longest)..<end {
                guard let before = best[start], let word = found[String(characters[start..<end])] else { continue }
                let score = before.score + log(word.weight / total)
                if score > best[end]?.score ?? -.infinity { best[end] = (score, before.syllables + word.syllables) }
            }
        }
        return best[characters.count]?.syllables
    }
}

extension PinyinDecoder {
    /// Keys that type `syllables` in the decoder's scheme, with an
    /// apostrophe only where the keys would otherwise read as other
    /// syllables (xi'an); nil when a syllable has no spelling.
    public func keys(typing syllables: [String]) -> String? {
        var keys = ""
        for (index, syllable) in syllables.enumerated() {
            guard let spelling = spellings[syllable] else { return nil }
            let expected = Array(syllables[...index])
            // librime reads keys as the fewest syllables they can be.
            let typed = keys + spelling
            if !keys.isEmpty, !self.syllables(typedAs: typed, count: expected.count - 1, limit: 1).isEmpty
                || self.syllables(typedAs: typed, count: expected.count, limit: 1).first != expected {
                keys += "'"
            }
            keys += spelling
        }
        return keys
    }
}
