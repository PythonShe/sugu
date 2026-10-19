import Foundation

/// Candidates Sugu computes itself from the reading: dates and times,
/// numerals, and arithmetic.
public struct ComputedCandidates: Sendable {
    public var calendar: Calendar
    public var timeZone: TimeZone

    public init(calendar: Calendar = Calendar(identifier: .gregorian), timeZone: TimeZone = .current) {
        var calendar = calendar
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.timeZone = timeZone
    }

    /// The prefix that turns the rest of a Chinese reading into a number or
    /// expression (`v123`, `v12*3`), as in common Chinese input methods.
    public static let chineseNumberPrefix: Character = "v"

    public func candidates(for reading: String, mode: InputMode, now: Date = Date()) -> [Candidate] {
        switch mode {
        case .chinese: chinese(reading.lowercased(), now: now)
        case .japanese: japanese(reading, now: now)
        case .english: []
        }
    }

    // MARK: Chinese

    private func chinese(_ reading: String, now: Date) -> [Candidate] {
        if reading.first == Self.chineseNumberPrefix, reading.count > 1 {
            return number(String(reading.dropFirst()), mode: .chinese)
        }
        let offsets = ["qiantian": -2, "zuotian": -1, "jintian": 0, "riqi": 0, "mingtian": 1, "houtian": 2]
        if let offset = offsets[reading], let date = calendar.date(byAdding: .day, value: offset, to: now) {
            return chineseDates(date).map { Candidate(text: $0, source: .computed) }
        }
        switch reading {
        case "shijian", "xianzai":
            return [format(now, "HH:mm"), format(now, "H点mm分"), format(now, "yyyy-MM-dd HH:mm")]
                .map { Candidate(text: $0, source: .computed) }
        case "xingqi", "zhouji":
            return [format(now, "EEEE", locale: "zh_CN"), format(now, "EEE", locale: "zh_CN")]
                .map { Candidate(text: $0, source: .computed) }
        default:
            return []
        }
    }

    private func chineseDates(_ date: Date) -> [String] {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = String(components.year ?? 0)
        let month = String(components.month ?? 0)
        let day = String(components.day ?? 0)
        let spelledYear = Numerals.spell(year, style: .positionalKanji) ?? year
        let spelledMonth = Numerals.spell(month, style: .chinese) ?? month
        let spelledDay = Numerals.spell(day, style: .chinese) ?? day
        return [
            "\(year)年\(month)月\(day)日",
            format(date, "yyyy-MM-dd"),
            "\(spelledYear)年\(spelledMonth)月\(spelledDay)日",
            "\(month)月\(day)日 " + format(date, "EEEE", locale: "zh_CN"),
        ]
    }

    // MARK: Japanese

    private func japanese(_ reading: String, now: Date) -> [Candidate] {
        let halfWidth = WidthConversion.halfWidth(reading)
        if halfWidth.allSatisfy({ $0.isASCIIDigitCharacter || "+-*/^%().".contains($0) || $0 == "ー" || $0 == "×" || $0 == "÷" }) {
            return number(halfWidth, mode: .japanese)
        }
        let offsets = ["おととい": -2, "きのう": -1, "きょう": 0, "ひづけ": 0, "あした": 1, "あす": 1, "あさって": 2]
        if let offset = offsets[reading], let date = calendar.date(byAdding: .day, value: offset, to: now) {
            return japaneseDates(date).map { Candidate(text: $0, source: .computed) }
        }
        switch reading {
        case "いま", "じこく":
            return [format(now, "H:mm"), format(now, "H時m分")].map { Candidate(text: $0, source: .computed) }
        case "ようび":
            return [format(now, "EEEE", locale: "ja_JP")].map { Candidate(text: $0, source: .computed) }
        default:
            return []
        }
    }

    private func japaneseDates(_ date: Date) -> [String] {
        let era = DateFormatter()
        era.calendar = Calendar(identifier: .japanese)
        era.locale = Locale(identifier: "ja_JP")
        era.timeZone = timeZone
        era.dateFormat = "GGGGy年M月d日"
        return [
            format(date, "yyyy年M月d日", locale: "ja_JP"),
            format(date, "yyyy/MM/dd", locale: "ja_JP"),
            era.string(from: date),
            format(date, "M月d日(E)", locale: "ja_JP"),
        ]
    }

    // MARK: Numbers

    private func number(_ text: String, mode: InputMode) -> [Candidate] {
        if let value = Arithmetic.evaluate(text) {
            let result = Arithmetic.format(value)
            return [result, "\(text)=\(result)"].map { Candidate(text: $0, source: .computed) }
        }
        guard text.allSatisfy({ $0.isASCIIDigitCharacter || $0 == "." }), text.filter({ $0 == "." }).count <= 1 else { return [] }
        let integer = String(text.split(separator: ".", omittingEmptySubsequences: false).first ?? "")
        var results: [String] = []
        switch mode {
        case .chinese:
            if !text.contains("."), let spelled = Numerals.spell(integer, style: .chinese) { results.append(spelled) }
            if !text.contains("."), let financial = Numerals.spell(integer, style: .chineseFinancial) { results.append(financial) }
            if let amount = Numerals.financialAmount(text) { results.append(amount) }
            results.append(WidthConversion.fullWidth(text))
            results.append(text)
        case .japanese:
            if !text.contains("."), let kanji = Numerals.spell(integer, style: .kanji) { results.append(kanji) }
            if !text.contains("."), let positional = Numerals.spell(integer, style: .positionalKanji) { results.append(positional) }
            results.append(WidthConversion.fullWidth(text))
        case .english:
            break
        }
        var seen = Set<String>()
        return results.filter { seen.insert($0).inserted }.map { Candidate(text: $0, source: .computed) }
    }

    private func format(_ date: Date, _ pattern: String, locale: String = "en_US_POSIX") -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: locale)
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
