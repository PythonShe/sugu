/// How a run of lower-case letters reads as romaji: whether a Japanese
/// typist could plausibly mean it, and as which kana. Stricter than the
/// engine's table, which also accepts `la`, `ca`, `qa` and `xa` as a way to
/// type kana that ordinary words do not need.
public struct RomajiReading: Sendable, Equatable {
    /// The whole input as hiragana; nil unless every letter is used.
    public var kana: String?
    /// Letters that belong to no syllable, leaving out a last few that may
    /// still become one (`watash`).
    public var strayLetters: Int
    /// Whether it has a letter romaji rarely uses: l, q, v, x, or c without h.
    public var hasForeignLetter: Bool

    /// Whether a Japanese typist is unlikely to have meant this as romaji.
    public var looksForeign: Bool { strayLetters > 0 || hasForeignLetter }

    private static let syllables: [String: String] = {
        var table: [String: String] = ["a": "あ", "i": "い", "u": "う", "e": "え", "o": "お"]
        let rows: [(String, [String])] = [
            ("k", ["か", "き", "く", "け", "こ"]), ("g", ["が", "ぎ", "ぐ", "げ", "ご"]),
            ("s", ["さ", "し", "す", "せ", "そ"]), ("z", ["ざ", "じ", "ず", "ぜ", "ぞ"]),
            ("t", ["た", "ち", "つ", "て", "と"]), ("d", ["だ", "ぢ", "づ", "で", "ど"]),
            ("n", ["な", "に", "ぬ", "ね", "の"]), ("h", ["は", "ひ", "ふ", "へ", "ほ"]),
            ("b", ["ば", "び", "ぶ", "べ", "ぼ"]), ("p", ["ぱ", "ぴ", "ぷ", "ぺ", "ぽ"]),
            ("m", ["ま", "み", "む", "め", "も"]), ("r", ["ら", "り", "る", "れ", "ろ"]),
        ]
        for (head, kana) in rows {
            for (vowel, mora) in zip(["a", "i", "u", "e", "o"], kana) { table[head + vowel] = mora }
        }
        let others = [
            "ya": "や", "yu": "ゆ", "yo": "よ", "wa": "わ", "wo": "を", "shi": "し", "chi": "ち", "tsu": "つ", "fu": "ふ",
            "ji": "じ", "fa": "ふぁ", "fi": "ふぃ", "fe": "ふぇ", "fo": "ふぉ", "wi": "うぃ", "we": "うぇ",
            "tsa": "つぁ", "thi": "てぃ", "dhi": "でぃ", "va": "ゔぁ", "vi": "ゔぃ", "vu": "ゔ", "ve": "ゔぇ", "vo": "ゔぉ",
        ]
        table.merge(others) { current, _ in current }
        let palatal = [
            ("ky", "き"), ("gy", "ぎ"), ("sh", "し"), ("sy", "し"), ("j", "じ"), ("zy", "じ"), ("jy", "じ"), ("ch", "ち"),
            ("ty", "ち"), ("dy", "ぢ"), ("ny", "に"), ("hy", "ひ"), ("by", "び"), ("py", "ぴ"), ("my", "み"), ("ry", "り"),
        ]
        for (head, mora) in palatal {
            table[head + "a"] = mora + "ゃ"
            table[head + "u"] = mora + "ゅ"
            table[head + "o"] = mora + "ょ"
            table[head + "e"] = mora + "ぇ"
        }
        return table
    }()

    private static let prefixes: Set<String> = {
        var prefixes = Set<String>()
        for syllable in syllables.keys {
            for length in 1..<max(syllable.count, 1) where length < syllable.count {
                prefixes.insert(String(syllable.prefix(length)))
            }
        }
        return prefixes
    }()

    private static let vowels: Set<UInt8> = Set("aiueo".utf8)

    public init(_ letters: String) {
        let bytes = Array(letters.utf8)
        let count = bytes.count
        // Fewest stray letters from each position to the end.
        var cost = Array(repeating: Int.max, count: count + 1)
        var step = Array(repeating: Step.stray, count: count + 1)
        cost[count] = 0
        for start in stride(from: count - 1, through: 0, by: -1) {
            var best = cost[start + 1] + 1
            var chosen = Step.stray
            for length in stride(from: min(3, count - start), through: 1, by: -1) {
                if Self.syllables[String(decoding: bytes[start..<(start + length)], as: UTF8.self)] != nil, cost[start + length] < best {
                    best = cost[start + length]
                    chosen = .syllable(length)
                }
            }
            if bytes[start] == UInt8(ascii: "n"), start + 1 == count || !(Self.vowels.contains(bytes[start + 1]) || bytes[start + 1] == UInt8(ascii: "y")), cost[start + 1] < best {
                best = cost[start + 1]
                chosen = .syllabicN
            }
            if start + 1 < count, bytes[start] == bytes[start + 1], !Self.vowels.contains(bytes[start]), bytes[start] != UInt8(ascii: "n"), cost[start + 1] < best {
                best = cost[start + 1]
                chosen = .doubled
            }
            // A syllable just begun, unless the letters already read whole.
            if best > 0, Self.prefixes.contains(String(decoding: bytes[start...], as: UTF8.self)) {
                best = 0
                chosen = .pending
            }
            cost[start] = best
            step[start] = chosen
        }
        strayLetters = cost[0]

        var kana = ""
        var position = 0
        walk: while position < count {
            switch step[position] {
            case .syllable(let length):
                kana += Self.syllables[String(decoding: bytes[position..<(position + length)], as: UTF8.self)] ?? ""
                position += length
            case .syllabicN:
                kana += "ん"
                position += 1
            case .doubled:
                kana += "っ"
                position += 1
            case .stray, .pending:
                break walk
            }
        }
        self.kana = position == count ? kana : nil

        hasForeignLetter = bytes.indices.contains { index in
            switch bytes[index] {
            case UInt8(ascii: "l"), UInt8(ascii: "q"), UInt8(ascii: "v"), UInt8(ascii: "x"): true
            case UInt8(ascii: "c"): index + 1 == count ? false : bytes[index + 1] != UInt8(ascii: "h")
            default: false
            }
        }
    }

    private enum Step {
        case stray, pending, syllabicN, doubled
        case syllable(Int)
    }
}
