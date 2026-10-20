import Foundation
import Testing
import SuguCore
@testable import SuguRime

private let dataDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Data")
private let hasData = FileManager.default.fileExists(atPath: dataDirectory.appendingPathComponent("Rime/wanxiang_algebra.yaml").path)

@Suite(.enabled(if: hasData))
struct PinyinDecoderTests {
    private func decoder(_ schema: RimeSchema = RimeSchema()) throws -> PinyinDecoder {
        let syllables = Lexicon.load(Lexicon.syllablesFile, in: dataDirectory.appendingPathComponent("Lexicon"))
        return try #require(PinyinDecoder(schema: schema, syllables: syllables, sharedData: dataDirectory.appendingPathComponent("Rime")))
    }

    /// Keys for syllables, with an apostrophe only where the keys would
    /// read otherwise.
    @Test func keysTypeSyllables() throws {
        #expect(try decoder().keys(typing: ["tong", "yi"]) == "tongyi")
        #expect(try decoder().keys(typing: ["xi", "an"]) == "xi'an")
        #expect(try decoder().keys(typing: ["fang", "an"]) == "fang'an")
        #expect(try decoder(RimeSchema(scheme: .xiaohe)).keys(typing: ["zhong", "guo"]) == "vsgo")
    }

    /// The likeliest split of text into listed words gives its reading.
    @Test func textReadsAsItsWords() throws {
        let list = Data("""
        长\tchang\t36122
        长\tzhang\t49072
        长城\tchang cheng\t30000
        城\tcheng\t20000
        银行\tyin hang\t40000
        行\txing\t90000
        银\tyin\t10000

        """.utf8)
        #expect(ChineseReadings.syllables(of: "长城", wordList: list) == ["chang", "cheng"])
        #expect(ChineseReadings.syllables(of: "银行", wordList: list) == ["yin", "hang"])
        #expect(ChineseReadings.syllables(of: "长", wordList: list) == ["zhang"])
        #expect(ChineseReadings.syllables(of: "长a", wordList: list) == nil)
    }

    /// The bundled word list and the decoder give keys librime reads back
    /// as the text's syllables.
    @Test func bundledTextReadsAsKeys() throws {
        let list = try Data(contentsOf: dataDirectory.appendingPathComponent("Lexicon/\(Lexicon.pinyinWordsFile)"), options: .mappedIfSafe)
        let decoder = try decoder()
        func keys(_ text: String) -> String? { ChineseReadings.syllables(of: text, wordList: list).flatMap(decoder.keys(typing:)) }
        #expect(keys("银行") == "yinhang")
        #expect(keys("西安") == "xi'an")
        #expect(keys("长城很长") == "changchenghenchang")
        #expect(keys("我们同意了") == "womentongyile")
    }

    @Test func fullPinyin() throws {
        let decoder = try decoder()
        #expect(decoder.syllables(typedAs: "zhangsanfeng", count: 3) == [["zhang", "san", "feng"]])
        // 嗯 is the syllable n, so xia + n types the same keys.
        #expect(decoder.syllables(typedAs: "xian", count: 2).contains(["xi", "an"]))
        #expect(decoder.syllables(typedAs: "xian", count: 1) == [["xian"]])
        #expect(decoder.syllables(typedAs: "lvse", count: 2) == [["lv", "se"]])
        #expect(decoder.syllables(typedAs: "zgr", count: 3).isEmpty)
        #expect(decoder.syllables(typedAs: "xi'an", count: 2) == [["xi", "an"]])
        #expect(decoder.syllables(typedAs: "xi'an", count: 1).isEmpty)
    }

    @Test func doublePinyin() throws {
        let xiaohe = try decoder(RimeSchema(scheme: .xiaohe))
        #expect(xiaohe.syllables(typedAs: "vhsjfg", count: 3) == [["zhang", "san", "feng"]])
        #expect(xiaohe.syllables(typedAs: "nihc", count: 2) == [["ni", "hao"]])
        #expect(xiaohe.syllables(typedAs: "zhangsanfeng", count: 3).isEmpty)
        let ziranma = try decoder(RimeSchema(scheme: .ziranma))
        #expect(ziranma.syllables(typedAs: "vhsjfg", count: 3) == [["zhang", "san", "feng"]])
    }

    @Test func fuzzyPinyinPrefersWhatWasTyped() throws {
        let decoder = try decoder(RimeSchema(fuzzy: [.zZh]))
        #expect(decoder.syllables(typedAs: "zangsan", count: 2) == [["zang", "san"]])
        let all = decoder.syllables(typedAs: "zangsan", count: 2, fewestDerivedOnly: false)
        #expect(all.first == ["zang", "san"])
        #expect(all.contains(["zhang", "san"]))
    }

    @Test func userDictionaryTable() throws {
        let xiaohe = try decoder(RimeSchema(scheme: .xiaohe))
        let words = [
            RimeUserDictionary.Word(reading: "vhsjfg", text: "张三丰", count: 2),
            // Imported full pinyin under a double-pinyin scheme.
            RimeUserDictionary.Word(reading: "linzhixia", text: "林知夏", count: 1),
            RimeUserDictionary.Word(reading: "ta", text: "她", count: 5),
            RimeUserDictionary.Word(reading: "tshirt", text: "T恤", count: 1),
            RimeUserDictionary.Word(reading: "zgr", text: "中国人", count: 1),
            RimeUserDictionary.Word(reading: "xi'an", text: "西安", count: 1),
        ]
        let table = RimeUserDictionary.table(for: words, decoder: xiaohe, fullPinyin: try decoder())
        let rows = table.split(separator: "\n").filter { !$0.hasPrefix("#") }
        #expect(rows == ["张三丰\tzhang san feng\t400000000", "林知夏\tlin zhi xia\t200000000"].sorted().map { Substring($0) })
    }

    @Test func userDictionaryKeepsTheFirstWordsWhenFull() throws {
        let decoder = try decoder()
        let words = (0..<(RimeUserDictionary.maximumWords + 10)).map { _ in RimeUserDictionary.Word(reading: "linzhixia", text: "林知夏", count: 1) }
            + [RimeUserDictionary.Word(reading: "chenyuchuan", text: "陈屿川", count: 1)]
        #expect(!RimeUserDictionary.table(for: words, decoder: decoder, fullPinyin: nil).contains("陈屿川"))
    }

    /// librime adds one to the count as a 32-bit integer.
    @Test func useCountsStayInLibrimeRange() {
        #expect(RimeUserDictionary.commits(uses: 0) == 200_000_000)
        #expect(RimeUserDictionary.commits(uses: 9) == 1_800_000_000)
        #expect(RimeUserDictionary.commits(uses: 1_000) == RimeUserDictionary.commits(uses: 9))
        #expect(RimeUserDictionary.commits(uses: 1_000) < Int(Int32.max))
    }

    @Test func readsRuleListsFromYAML() {
        let yaml = """
        top:
          __append:
            - xform/a/b/  # comment
        lite:
          全拼:
            __append:
              - derive/^l/n
              - "xlit/ab/cd/"
          自然码:
            __append:
              - xform/x/y/
        """
        #expect(SpellingAlgebra.rules(at: ["lite", "全拼", "__append"], inYAML: yaml) == ["derive/^l/n", "xlit/ab/cd/"])
        #expect(SpellingAlgebra.rules(at: ["top", "__append"], inYAML: yaml) == ["xform/a/b/"])
        #expect(SpellingAlgebra.rules(at: ["missing", "__append"], inYAML: yaml) == nil)
    }
}
