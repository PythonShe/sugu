import Foundation
import Testing
import SuguAzooKey
import SuguCore
import SuguLM
@testable import SuguRime

@MainActor
@Suite struct SentenceRespellerTests {
    private let words = PinyinWords(lines: [
        "我们\two men\t500", "去\tqu\t400", "吃\tchi\t400", "完\twan\t300", "晚\twan\t200",
        "饭\tfan\t300", "吃完\tchi wan\t100", "晚饭\twan fan\t100",
    ])
    private let reading = [["wo", "men", "qu", "chi", "wan", "fan"]]

    private func respeller() throws -> SentenceRespeller {
        try SentenceRespeller(model: testLanguageModel(["我们去吃晚饭吧。", "晚饭吃什么？", "今天的晚饭很好吃。"]), words: words)
    }

    @Test func respellsWhatTheModelReadsAsClearlyBetter() throws {
        #expect(try respeller().respelled("我们去吃完饭", readings: reading, after: "") == "我们去吃晚饭")
        #expect(try respeller().respelled("我们去吃晚饭", readings: reading, after: "") == nil)
    }

    /// One word typed after text: the text decides, by a smaller margin;
    /// alone, librime's word stands.
    @Test func aWordFollowsTheTextBeforeIt() throws {
        let words = PinyinWords(lines: ["大学\tda xue\t500", "大雪\tda xue\t300"])
        let model = try testLanguageModel(["昨天下了一场大雪。", "今年的第一场大雪。", "他在大学学习。", "大学很大。"])
        let respeller = SentenceRespeller(model: model, words: words)
        #expect(respeller.respelled("大学", readings: [["da", "xue"]], after: "昨天晚上下了一场") == "大雪")
        #expect(respeller.respelled("大学", readings: [["da", "xue"]], after: "") == nil)
    }

    /// A character in another script that reaches a Simplified sentence is
    /// read in Simplified and leaves in Simplified, rather than making its
    /// word unknown to the model.
    @Test(.enabled(if: hasEngineData)) func aSimplifiedSentenceIsReadInSimplified() throws {
        let openCC = engineDataDirectory.appendingPathComponent("Rime/opencc")
        let respelling = ChineseRespelling(respeller: try respeller()) { ScriptConverter.toScript($0, openCC: openCC) }
        #expect(respelling.respelled("我们去吃晚飯", readings: reading, after: "", script: .simplified) == "我们去吃晚饭")
        #expect(respelling.respelled("我们去吃完飯", readings: reading, after: "", script: .simplified) == "我们去吃晚饭")
        #expect(respelling.respelled("我们去吃晚饭", readings: reading, after: "", script: .simplified) == nil)
    }

    @Test func keepsTheUsersWords() throws {
        let respeller = try respeller()
        respeller.userWords = ["吃完饭"]
        #expect(respeller.respelled("我们去吃完饭", readings: reading, after: "") == nil)
    }

    @Test func leavesTextOutsideTheWordList() throws {
        #expect(try respeller().respelled("我们去吃完面", readings: [["wo", "men", "qu", "chi", "wan", "mian"]], after: "") == nil)
    }
}
