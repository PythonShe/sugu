extension Unicode.Scalar {
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
