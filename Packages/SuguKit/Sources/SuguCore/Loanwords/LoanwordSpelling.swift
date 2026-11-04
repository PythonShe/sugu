import Foundation

/// The form foreign spellings are stored and looked up in: lower-case ASCII
/// with marks, spaces and joining punctuation gone, since a Latin keyboard
/// types `cafe` and `muller` for café and Müller.
public enum LoanwordSpelling {
    /// Letters NFKD leaves whole.
    private static let replacements: [Character: String] = [
        "ß": "ss", "ẞ": "ss", "æ": "ae", "Æ": "ae", "œ": "oe", "Œ": "oe", "ø": "o", "Ø": "o",
        "ð": "d", "Ð": "d", "þ": "th", "Þ": "th", "ł": "l", "Ł": "l", "đ": "d", "Đ": "d",
        "ı": "i", "ħ": "h", "ŋ": "n",
    ]
    private static let dropped: Set<Character> = [" ", "\t", "-", "'", "’", "ʻ", "ʼ", ".", "‐", "·", "・", "&", "_", "　"]

    /// The key for a spelling; nil when it holds anything other than letters
    /// and digits once folded, or no letter at all.
    public static func key(_ spelling: String) -> String? {
        var folded = spelling
        if !spelling.utf8.allSatisfy({ $0 < 0x80 }) {
            var replaced = ""
            for character in spelling { replaced += replacements[character] ?? String(character) }
            folded = replaced.decomposedStringWithCompatibilityMapping
        }
        var key = ""
        var hasLetter = false
        for scalar in folded.unicodeScalars {
            if scalar.properties.generalCategory == .nonspacingMark { continue }
            if dropped.contains(Character(scalar)) { continue }
            switch scalar.value {
            case 0x41...0x5A:
                key.unicodeScalars.append(Unicode.Scalar(scalar.value + 0x20)!)
                hasLetter = true
            case 0x61...0x7A:
                key.unicodeScalars.append(scalar)
                hasLetter = true
            case 0x30...0x39:
                key.unicodeScalars.append(scalar)
            default:
                return nil
            }
        }
        return hasLetter ? key : nil
    }
}
