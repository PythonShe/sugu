import Testing
@testable import SuguCore

struct TextTests {
    @Test func widths() {
        #expect(WidthConversion.fullWidth("Ab1 !") == "Ａｂ１　！")
        #expect(WidthConversion.halfWidth("Ａｂ１　！") == "Ab1 !")
    }

    @Test func kana() {
        #expect(WidthConversion.katakana("にほんご") == "ニホンゴ")
        #expect(WidthConversion.hiragana("ニホンゴ") == "にほんご")
        #expect(WidthConversion.halfWidthKatakana("がっこう。") == "ｶﾞｯｺｳ｡")
    }

    @Test func automaticPunctuationWidth() {
        var punctuator = ChinesePunctuator()
        #expect(punctuator.output(for: ",", after: "好") == "，")
        #expect(punctuator.output(for: ".", after: "3") == ".")
        #expect(punctuator.output(for: ",", after: "a") == ",")
        #expect(punctuator.output(for: "\\", after: "a") == "、")
        #expect(punctuator.output(for: ".", after: nil) == "。")
    }

    @Test func pairedQuotesAlternate() {
        var punctuator = ChinesePunctuator(width: .full)
        #expect(punctuator.output(for: "\"", after: nil) == "“")
        #expect(punctuator.output(for: "\"", after: "好") == "”")
        #expect(punctuator.output(for: "'", after: nil) == "‘")
    }

    @Test func modeCycleSkipsDisabledModes() {
        #expect(InputMode.chinese.next(enabled: [.chinese, .japanese]) == .japanese)
        #expect(InputMode.japanese.next(enabled: [.chinese, .japanese]) == .english)
        #expect(InputMode.chinese.next(enabled: [.chinese]) == .english)
    }
}
