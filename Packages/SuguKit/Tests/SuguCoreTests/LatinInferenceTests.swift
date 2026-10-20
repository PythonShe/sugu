import Testing
@testable import SuguCore

struct LatinInferenceTests {
    // A handful of syllables is enough to exercise segmentation.
    let inference = LatinInference(
        syllables: ["ni", "hao", "zhong", "guo", "ren", "ming", "a", "ma", "xi", "an"],
        englishWords: ["hello", "github", "xian"],
        allowList: ["nb"]
    )

    @Test func segmentation() {
        #expect(inference.isPinyin("nihao"))
        #expect(inference.isPinyin("zhongg"))
        #expect(inference.isPinyin("xi'an"))
        #expect(!inference.isPinyin("github"))
        #expect(inference.isFullSyllables("zhongguo"))
        #expect(!inference.isFullSyllables("zhongg"))
    }

    @Test func placement() {
        #expect(inference.placement(for: "nihao") == .last)
        #expect(inference.placement(for: "github") == .first)
        #expect(inference.placement(for: "v2") == .first)
        #expect(inference.placement(for: "Nihao") == .first)
        #expect(inference.placement(for: "nb") == .first)
        // Valid pinyin that is also an English word stays pinyin.
        #expect(inference.placement(for: "xian") == .last)
    }

    @Test func syllablesFromToneMarkedDictionary() {
        let dictionary = "绿\tlǜ\t1\n略\tlüè\t1\n女\tnǚ\t1\n好\thǎo\t1\n"
        #expect(Lexicon.syllables(fromRimeDictionary: dictionary) == ["lv", "lve", "nv", "hao"])
    }
}
