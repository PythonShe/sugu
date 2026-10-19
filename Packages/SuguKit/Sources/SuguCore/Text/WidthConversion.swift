/// Conversions behind the F6–F10 keys and width-aware output.
public enum WidthConversion {
    /// ASCII printable → full-width forms (U+FF01–FF5E), space → U+3000.
    public static func fullWidth(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x20: return Unicode.Scalar(0x3000)!
            case 0x21...0x7E: return Unicode.Scalar(scalar.value + 0xFEE0)!
            default: return scalar
            }
        }))
    }

    /// Full-width forms → ASCII, U+3000 → space.
    public static func halfWidth(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x3000: return Unicode.Scalar(0x20)!
            case 0xFF01...0xFF5E: return Unicode.Scalar(scalar.value - 0xFEE0)!
            default: return scalar
            }
        }))
    }

    /// Hiragana → katakana.
    public static func katakana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (0x3041...0x3096).contains(scalar.value) || (0x309D...0x309E).contains(scalar.value)
                ? Unicode.Scalar(scalar.value + 0x60)! : scalar
        }))
    }

    /// Katakana → hiragana.
    public static func hiragana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (0x30A1...0x30F6).contains(scalar.value) || (0x30FD...0x30FE).contains(scalar.value)
                ? Unicode.Scalar(scalar.value - 0x60)! : scalar
        }))
    }

    /// Kana → half-width katakana, splitting voiced marks.
    public static func halfWidthKatakana(_ text: String) -> String {
        var result = ""
        for scalar in katakana(text).unicodeScalars {
            if let mapped = halfWidthKana[scalar] {
                result += mapped
            } else if let full = Self.fullToHalfPunctuation[scalar] {
                result.unicodeScalars.append(full)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    private static let fullToHalfPunctuation: [Unicode.Scalar: Unicode.Scalar] = [
        "。": "｡", "「": "｢", "」": "｣", "、": "､", "・": "･", "ー": "ｰ",
    ]

    private static let halfWidthKana: [Unicode.Scalar: String] = {
        let full = Array("ァアィイゥウェエォオカガキギクグケゲコゴサザシジスズセゼソゾタダチヂッツヅテデトドナニヌネノハバパヒビピフブプヘベペホボポマミムメモャヤュユョヨラリルレロヮワヰヱヲンヴヵヶ".unicodeScalars)
        let half = ["ｧ", "ｱ", "ｨ", "ｲ", "ｩ", "ｳ", "ｪ", "ｴ", "ｫ", "ｵ", "ｶ", "ｶﾞ", "ｷ", "ｷﾞ", "ｸ", "ｸﾞ", "ｹ", "ｹﾞ", "ｺ", "ｺﾞ",
                    "ｻ", "ｻﾞ", "ｼ", "ｼﾞ", "ｽ", "ｽﾞ", "ｾ", "ｾﾞ", "ｿ", "ｿﾞ", "ﾀ", "ﾀﾞ", "ﾁ", "ﾁﾞ", "ｯ", "ﾂ", "ﾂﾞ", "ﾃ", "ﾃﾞ", "ﾄ", "ﾄﾞ",
                    "ﾅ", "ﾆ", "ﾇ", "ﾈ", "ﾉ", "ﾊ", "ﾊﾞ", "ﾊﾟ", "ﾋ", "ﾋﾞ", "ﾋﾟ", "ﾌ", "ﾌﾞ", "ﾌﾟ", "ﾍ", "ﾍﾞ", "ﾍﾟ", "ﾎ", "ﾎﾞ", "ﾎﾟ",
                    "ﾏ", "ﾐ", "ﾑ", "ﾒ", "ﾓ", "ｬ", "ﾔ", "ｭ", "ﾕ", "ｮ", "ﾖ", "ﾗ", "ﾘ", "ﾙ", "ﾚ", "ﾛ", "ﾜ", "ﾜ", "ｲ", "ｴ", "ｦ", "ﾝ", "ｳﾞ", "ｶ", "ｹ"]
        return Dictionary(uniqueKeysWithValues: zip(full, half))
    }()
}
