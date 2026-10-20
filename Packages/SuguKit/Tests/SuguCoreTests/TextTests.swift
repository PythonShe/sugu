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

    @Test func kanaLayout() {
        #expect(KanaLayout.kana(forKeyCode: 0x11, shift: false, jis: true) == "か")
        #expect(KanaLayout.kana(forKeyCode: 0x11, shift: true, jis: true) == "か")
        #expect(KanaLayout.kana(forKeyCode: 0x06, shift: true, jis: false) == "っ")
        #expect(KanaLayout.kana(forKeyCode: 0x5D, shift: false, jis: true) == "ー")
        #expect(KanaLayout.kana(forKeyCode: 0x27, shift: true, jis: false) == "ろ")
        #expect(KanaLayout.kana(forKeyCode: 0x31, shift: false, jis: true) == nil)
        #expect(KanaLayout.applying(KanaLayout.voicedMark, to: "う") == "ゔ")
        #expect(KanaLayout.applying(KanaLayout.semiVoicedMark, to: "ひ") == "ぴ")
        #expect(KanaLayout.applying(KanaLayout.semiVoicedMark, to: "か") == nil)
    }

    @Test func automaticPunctuationWidth() {
        var punctuator = ChinesePunctuator()
        #expect(punctuator.output(for: ",", after: "好") == "，")
        #expect(punctuator.output(for: ".", after: "3") == ".")
        #expect(punctuator.output(for: ",", after: "a") == ",")
        #expect(punctuator.output(for: "\\", after: "a") == "、")
        #expect(punctuator.output(for: ".", after: nil) == "。")
    }

    @Test func romajiSymbols() {
        let style = JapanesePunctuationStyle.touten
        #expect(style.romajiInput(for: "-") == "ー")
        #expect(style.romajiInput(for: "[") == "「")
        #expect(style.romajiInput(for: "/") == "・")
        #expect(style.romajiInput(for: "?") == "？")
        #expect(style.romajiInput(for: "k") == "k")
        #expect(style.romajiInput(for: "3") == "3")
        #expect(JapanesePunctuationStyle.commaPeriod.romajiInput(for: ".") == "．")
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
