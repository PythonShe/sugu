/// Spelled-out numerals for Chinese and Japanese.
public enum Numerals {
    public enum Style: Sendable {
        /// 一千二百三十四
        case chinese
        /// 壹仟贰佰叁拾肆
        case chineseFinancial
        /// 千二百三十四
        case kanji
        /// 一二三四
        case positionalKanji
    }

    private static let chineseDigits: [Character] = Array("零一二三四五六七八九")
    private static let financialDigits: [Character] = Array("零壹贰叁肆伍陆柒捌玖")
    private static let positionalDigits: [Character] = Array("〇一二三四五六七八九")

    /// Spells a non-negative integer of up to 16 digits.
    public static func spell(_ digits: String, style: Style) -> String? {
        guard !digits.isEmpty, digits.count <= 16, digits.allSatisfy(\.isASCIIDigitCharacter) else { return nil }
        let table = digitTable(style)
        if style == .positionalKanji {
            return String(digits.map { table[$0.asciiDigitValue] })
        }
        let trimmed = Array(digits.drop { $0 == "0" })
        if trimmed.isEmpty { return style == .kanji ? "〇" : String(table[0]) }
        let groups = chunks(of: trimmed, size: 4)
        let groupUnits = style == .kanji ? ["", "万", "億", "兆"] : ["", "万", "亿", "万亿"]
        var result = ""
        var skippedZeroGroup = false
        for (offset, group) in groups.enumerated() {
            let value = Int(String(group)) ?? 0
            if value == 0 {
                skippedZeroGroup = true
                continue
            }
            // Chinese reads a gap of zeros between groups as one 零.
            if style != .kanji, !result.isEmpty, skippedZeroGroup || value < 1000 {
                result.append(table[0])
            }
            skippedZeroGroup = false
            let omitLeadingOne = style == .chinese && offset == 0 && group.count == 2
            result += spellGroup(group, style: style, omitLeadingOne: omitLeadingOne)
            result += groupUnits[groups.count - 1 - offset]
        }
        return result
    }

    /// Spells one group of up to four digits. Chinese keeps 零 between
    /// non-zero digits; Japanese drops it and omits 一 before 十, 百 and 千.
    private static func spellGroup(_ group: [Character], style: Style, omitLeadingOne: Bool) -> String {
        let table = digitTable(style)
        let units = style == .chineseFinancial ? ["仟", "佰", "拾", ""] : ["千", "百", "十", ""]
        let padded = Array(repeating: Character("0"), count: 4 - group.count) + group
        var text = ""
        var pendingZero = false
        for (index, c) in padded.enumerated() {
            let value = c.asciiDigitValue
            if value == 0 {
                pendingZero = !text.isEmpty
                continue
            }
            if pendingZero, style != .kanji { text.append(table[0]) }
            pendingZero = false
            let unit = units[index]
            let omitOne = value == 1 && !unit.isEmpty
                && (style == .kanji || (omitLeadingOne && unit == "十" && text.isEmpty))
            if !omitOne { text.append(table[value]) }
            text += unit
        }
        return text
    }

    private static func digitTable(_ style: Style) -> [Character] {
        switch style {
        case .chineseFinancial: financialDigits
        case .positionalKanji: positionalDigits
        default: chineseDigits
        }
    }

    private static func chunks(of digits: [Character], size: Int) -> [[Character]] {
        var result: [[Character]] = []
        var end = digits.count
        while end > 0 {
            let start = max(0, end - size)
            result.insert(Array(digits[start..<end]), at: 0)
            end = start
        }
        return result
    }

    /// Financial amount: 壹仟贰佰叁拾肆元伍角陆分 / …元整.
    public static func financialAmount(_ number: String) -> String? {
        let parts = number.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, let integer = parts.first, let spelled = spell(String(integer.isEmpty ? "0" : integer), style: .chineseFinancial) else { return nil }
        var result = spelled + "元"
        let fraction = parts.count == 2 ? Array(parts[1]) : []
        guard fraction.allSatisfy(\.isASCIIDigitCharacter), fraction.count <= 2 else { return nil }
        let jiao = fraction.first.map(\.asciiDigitValue) ?? 0
        let fen = fraction.count > 1 ? fraction[1].asciiDigitValue : 0
        if jiao == 0 && fen == 0 {
            return result + "整"
        }
        if jiao > 0 { result += String(financialDigits[jiao]) + "角" } else if fen > 0 { result += "零" }
        if fen > 0 { result += String(financialDigits[fen]) + "分" }
        return result
    }
}

extension Character {
    public var isASCIIDigitCharacter: Bool { unicodeScalars.count == 1 && (0x30...0x39).contains(unicodeScalars.first!.value) }
    public var asciiDigitValue: Int { Int(unicodeScalars.first!.value) - 0x30 }
}
