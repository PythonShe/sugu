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
}
