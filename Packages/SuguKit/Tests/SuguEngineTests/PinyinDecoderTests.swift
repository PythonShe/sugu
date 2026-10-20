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
