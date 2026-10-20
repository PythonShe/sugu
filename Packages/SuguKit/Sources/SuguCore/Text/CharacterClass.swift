extension Unicode.Scalar {
    /// Han ideographs, kana, and CJK symbols — text after which full-width
    /// punctuation reads naturally.
    public var isCJK: Bool {
        switch value {
        case 0x3000...0x303F, // CJK symbols and punctuation
             0x3040...0x30FF, // hiragana, katakana
             0x3400...0x4DBF, // extension A
             0x4E00...0x9FFF, // unified ideographs
             0xF900...0xFAFF, // compatibility ideographs
             0xFF00...0xFFEF, // half-width and full-width forms
             0x20000...0x323AF: // extensions B–H
            return true
        default:
            return false
        }
    }

    /// Han ideographs: unified, extensions, and compatibility.
    public var isHan: Bool { properties.isIdeographic }

    /// Hiragana, including ゝゞ.
    public var isHiragana: Bool { (0x3041...0x309F).contains(value) }

    /// Hiragana or katakana, including ー.
    public var isKana: Bool { (0x3041...0x30FF).contains(value) }

    public var isASCIILetterOrDigit: Bool {
        switch value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true
        default: return false
        }
    }
}

extension StringProtocol {
    /// A Japanese reading as Sugu stores it: hiragana and ー only.
    public var isHiraganaReading: Bool {
        !isEmpty && unicodeScalars.allSatisfy { $0.isHiragana || $0.value == 0x30FC }
    }
}

extension Character {
    public var isCJK: Bool { unicodeScalars.first?.isCJK ?? false }
    public var isHan: Bool { unicodeScalars.count == 1 && (unicodeScalars.first?.isHan ?? false) }
    public var isASCIILetterOrDigit: Bool {
        unicodeScalars.count == 1 && (unicodeScalars.first?.isASCIILetterOrDigit ?? false)
    }
    public var isASCIILetter: Bool { isASCII && isLetter }
}

extension Character {
    /// a–z only.
    public var isASCIILowercaseLetter: Bool {
        guard unicodeScalars.count == 1, let value = unicodeScalars.first?.value else { return false }
        return (0x61...0x7A).contains(value)
    }
}
