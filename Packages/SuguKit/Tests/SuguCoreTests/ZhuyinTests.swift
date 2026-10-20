import Foundation
import Testing
import SuguCore

struct ZhuyinTests {
    private let syllabary: [String] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Data/Lexicon/pinyin-syllables.txt")
        return ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }()

    /// Every syllable but the nasal interjections (m, n, ng) has one
    /// spelling, which reads back as the same pinyin.
    @Test func everySyllableHasOneZhuyinSpelling() throws {
        try #require(!syllabary.isEmpty)
        let spelled = Zhuyin.syllables(of: syllabary)
        #expect(Set(syllabary.filter { spelled[$0] == nil }) == ["m", "n", "ng"])
        for (pinyin, syllable) in spelled {
            #expect(Zhuyin.Syllable(syllable.symbols)?.pinyin == pinyin)
        }
        // No two spellings write the same syllable.
        let symbols = Set(Zhuyin.keyboard.values)
        var seen: [String: String] = [:]
        for initial in [nil] + symbols.filter({ Zhuyin.slot(of: $0) == .initial }) as [Character?] {
            for medial in [nil] + symbols.filter({ Zhuyin.slot(of: $0) == .medial }) as [Character?] {
                for final in [nil] + symbols.filter({ Zhuyin.slot(of: $0) == .final }) as [Character?] {
                    let syllable = Zhuyin.Syllable(initial: initial, medial: medial, final: final)
                    guard let pinyin = syllable.pinyin, spelled[pinyin] != nil else { continue }
                    #expect(seen[pinyin] == nil, "\(pinyin): \(seen[pinyin] ?? "") and \(syllable.symbols)")
                    seen[pinyin] = syllable.symbols
                }
            }
        }
    }

    @Test func syllablesSpellAsTheStandardWritesThem() {
        let cases: [(String, String)] = [
            ("ㄓ", "zhi"), ("ㄗ", "zi"), ("ㄧ", "yi"), ("ㄨ", "wu"), ("ㄩ", "yu"), ("ㄧㄣ", "yin"), ("ㄧㄥ", "ying"),
            ("ㄨㄥ", "weng"), ("ㄩㄥ", "yong"), ("ㄉㄨㄥ", "dong"), ("ㄒㄩㄥ", "xiong"), ("ㄐㄩ", "ju"), ("ㄋㄩ", "nv"),
            ("ㄌㄩㄝ", "lve"), ("ㄐㄩㄝ", "jue"), ("ㄉㄧㄡ", "diu"), ("ㄍㄨㄟ", "gui"), ("ㄌㄨㄣ", "lun"), ("ㄅㄛ", "bo"),
            ("ㄉㄜ", "de"), ("ㄦ", "er"), ("ㄧㄝ", "ye"), ("ㄩㄢ", "yuan"),
        ]
        for (symbols, pinyin) in cases { #expect(Zhuyin.Syllable(symbols)?.pinyin == pinyin, "\(symbols)") }
        #expect(Zhuyin.Syllable("ㄉㄝ")?.pinyin == nil)
    }

    @Test func tonesAreWrittenAndCoded() {
        let ni = Zhuyin.Syllable("ㄋㄧˇ")
        #expect(ni?.tone == .third && ni?.code == "ni3" && ni?.text == "ㄋㄧˇ")
        let de = Zhuyin.Syllable("˙ㄉㄜ")
        #expect(de?.code == "de5" && de?.text == "˙ㄉㄜ")
        #expect(Zhuyin.Syllable("ㄇㄚ")?.code == "ma1")
        #expect(Zhuyin.Syllable("ㄋㄧˇˇ") == nil)
    }

    /// Typing a symbol fills its slot, replacing the one there.
    @Test func typingReplacesASlot() {
        var syllable = Zhuyin.Syllable()
        for key in "su3" where Zhuyin.toneKeys[key] == nil { syllable.type(Zhuyin.keyboard[key]!) }
        #expect(syllable.symbols == "ㄋㄧ")
        syllable.type("ㄌ")
        #expect(syllable.symbols == "ㄌㄧ")
        syllable.deleteLast()
        #expect(syllable.symbols == "ㄌ")
    }

    @Test func dictionaryPinyinBecomesCodes() {
        let cases = ["nǐ": "ni3", "hǎo": "hao3", "de": "de5", "lǜ": "lv4", "nüè": "nve4", "ā": "a1", "ń": "n2", "zhōng": "zhong1"]
        for (pinyin, code) in cases { #expect(Zhuyin.code(ofTonedPinyin: pinyin) == code, "\(pinyin)") }
    }
}

extension ZhuyinTests {
    @Test func syllablesTypeOnTheirKeys() throws {
        let syllables = try #require(Zhuyin.syllables(ofCodes: "ni3hao3ma1de5"))
        #expect(syllables.map(Zhuyin.keys(typing:)).joined() == "su3cl3a8 2k7")
    }
}
