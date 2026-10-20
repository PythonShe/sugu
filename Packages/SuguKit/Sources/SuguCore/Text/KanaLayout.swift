import Foundation

/// The kana each physical key types in kana input, as on the Mac's
/// Japanese input method: the JIS kana layout on JIS keyboards, and its
/// ANSI arrangement elsewhere (け, ろ, ー and the voicing marks move to the
/// keys an ANSI keyboard has). Keyed by macOS virtual key code, so it does
/// not depend on the Latin layout in use.
public enum KanaLayout {
    /// Voiced and semi-voiced marks, typed after the kana they change.
    public static let voicedMark: Character = "゛"
    public static let semiVoicedMark: Character = "゜"

    public static func kana(forKeyCode code: UInt16, shift: Bool, jis: Bool) -> String? {
        let table = jis ? (shift ? jisShifted : jisPlain) : (shift ? ansiShifted : ansiPlain)
        return table[code] ?? (shift ? (jis ? jisPlain : ansiPlain)[code] : nil)
    }

    /// The kana a voicing mark makes of `kana` (か + ゛ → が, は + ゜ → ぱ),
    /// or nil when it takes none.
    public static func applying(_ mark: Character, to kana: Character) -> Character? {
        let combining: Unicode.Scalar = mark == voicedMark ? "\u{3099}" : "\u{309A}"
        let composed = (String(kana) + String(combining)).precomposedStringWithCanonicalMapping
        guard composed.count == 1, composed.unicodeScalars.count == 1, let result = composed.first else { return nil }
        return result
    }

    private static let letters: [UInt16: String] = [
        0x0C: "た", 0x0D: "て", 0x0E: "い", 0x0F: "す", 0x11: "か", 0x10: "ん", 0x20: "な", 0x22: "に", 0x1F: "ら", 0x23: "せ",
        0x00: "ち", 0x01: "と", 0x02: "し", 0x03: "は", 0x05: "き", 0x04: "く", 0x26: "ま", 0x28: "の", 0x25: "り",
        0x06: "つ", 0x07: "さ", 0x08: "そ", 0x09: "ひ", 0x0B: "こ", 0x2D: "み", 0x2E: "も",
        0x12: "ぬ", 0x13: "ふ", 0x14: "あ", 0x15: "う", 0x17: "え", 0x16: "お", 0x1A: "や", 0x1C: "ゆ", 0x19: "よ", 0x1D: "わ",
        0x29: "れ", 0x2B: "ね", 0x2F: "る", 0x2C: "め", 0x1B: "ほ",
    ]

    private static let smallKana: [UInt16: String] = [
        0x14: "ぁ", 0x15: "ぅ", 0x17: "ぇ", 0x16: "ぉ", 0x1A: "ゃ", 0x1C: "ゅ", 0x19: "ょ", 0x1D: "を",
        0x0E: "ぃ", 0x06: "っ", 0x2B: "、", 0x2F: "。", 0x2C: "・",
    ]

    private static let jisPlain = letters.merging([
        0x18: "へ", 0x5D: "ー", 0x21: "゛", 0x1E: "゜", 0x27: "け", 0x2A: "む", 0x5E: "ろ",
    ]) { $1 }
    private static let jisShifted = smallKana.merging([0x1E: "「", 0x2A: "」"]) { $1 }

    private static let ansiPlain = letters.merging([
        0x2A: "へ", 0x21: "゛", 0x18: "゜", 0x27: "け", 0x1E: "む",
    ]) { $1 }
    private static let ansiShifted = smallKana.merging([0x18: "「", 0x21: "」", 0x1E: "ー", 0x27: "ろ"]) { $1 }
}
