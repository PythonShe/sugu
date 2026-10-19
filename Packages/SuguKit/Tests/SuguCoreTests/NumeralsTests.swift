import Testing
@testable import SuguCore

struct NumeralsTests {
    @Test(arguments: [
        ("0", "零"), ("7", "七"), ("10", "十"), ("15", "十五"), ("110", "一百一十"),
        ("1004", "一千零四"), ("1040", "一千零四十"), ("10004", "一万零四"),
        ("100000", "十万"), ("100000001", "一亿零一"), ("123456", "十二万三千四百五十六"),
    ])
    func chinese(_ input: String, _ expected: String) {
        #expect(Numerals.spell(input, style: .chinese) == expected)
    }

    @Test(arguments: [("1234", "壹仟贰佰叁拾肆"), ("10", "壹拾"), ("1004", "壹仟零肆")])
    func financial(_ input: String, _ expected: String) {
        #expect(Numerals.spell(input, style: .chineseFinancial) == expected)
    }

    @Test(arguments: [("1", "一"), ("10", "十"), ("1100", "千百"), ("1004", "千四"), ("10000", "一万"), ("2026", "二千二十六")])
    func kanji(_ input: String, _ expected: String) {
        #expect(Numerals.spell(input, style: .kanji) == expected)
    }

    @Test func positional() {
        #expect(Numerals.spell("2026", style: .positionalKanji) == "二〇二六")
    }

    @Test func financialAmount() {
        #expect(Numerals.financialAmount("1234") == "壹仟贰佰叁拾肆元整")
        #expect(Numerals.financialAmount("12.5") == "壹拾贰元伍角")
        #expect(Numerals.financialAmount("3.05") == "叁元零伍分")
    }

    @Test func rejectsNonDigits() {
        #expect(Numerals.spell("12a", style: .chinese) == nil)
        #expect(Numerals.spell("", style: .chinese) == nil)
    }
}
