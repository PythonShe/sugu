import Testing
import SuguCore
@testable import SuguRime

struct ZhuyinCodeTests {
    /// The schema's tone rules write each reading as Zhuyin reads it.
    @Test func toneRulesWriteTheCodesZhuyinTypes() {
        let algebra = SpellingAlgebra(rules: Zhuyin.toneRules)
        let readings = ["a", "ā", "nǐ", "hǎo", "de", "lǜ", "lüè", "nüè", "xué", "zhuàng", "ér", "ń", "ňg", "ḿ", "m\u{300}", "ōu", "yīng", "qióng"]
        for reading in readings {
            #expect(algebra.spellings(of: reading).map(\.text) == [Zhuyin.code(ofTonedPinyin: reading)], "\(reading)")
        }
    }

    /// Codes written back as the dictionary writes them, which its tone
    /// rules read as the same codes.
    @Test func codesBecomeTheDictionarysSyllables() {
        let algebra = SpellingAlgebra(rules: Zhuyin.toneRules)
        for (code, written) in [("ni3", "nǐ"), ("hao3", "hǎo"), ("lve4", "lüè"), ("lv4", "lǜ"), ("de5", "de"), ("gou3", "gǒu"), ("gui4", "guì"), ("liu2", "liú"), ("xue2", "xué"), ("er2", "ér")] {
            #expect(Zhuyin.tonedPinyin(ofCode: code) == written)
            #expect(algebra.spellings(of: written).map(\.text) == [code])
        }
    }
}
