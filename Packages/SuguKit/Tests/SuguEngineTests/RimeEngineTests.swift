import Foundation
import Testing
import SuguAzooKey
import SuguCore
import SuguLM
import SuguRime

@MainActor
@Suite(.serialized, .enabled(if: hasEngineData))
struct RimeEngineTests {
    private func first(_ reading: String, schema: RimeSchema = RimeSchema(), script: ChineseScript = .simplified) async throws -> String? {
        try await Shared.runtime.prepare(schema, version: "test")
        let engine = RimeEngine(runtime: Shared.runtime, script: script)
        engine.insert(reading)
        defer { engine.clear() }
        return engine.state.candidates.first?.text
    }

    /// A word that names an emoji offers it right after the word, in
    /// either script.
    @Test func wordsOfferTheirEmoji() async throws {
        try await Shared.runtime.prepare(RimeSchema(), version: "test")
        for (reading, script, word, emoji) in [
            ("tongyi", ChineseScript.simplified, "同意", "👍"), ("aixin", .traditional, "愛心", "❤️"),
            ("jiantou", .simplified, "箭头", "→"), ("sheshidu", .traditional, "攝氏度", "℃"),
        ] {
            let engine = RimeEngine(runtime: Shared.runtime, script: script)
            engine.insert(reading)
            let texts = engine.state.candidates.map(\.text)
            engine.clear()
            let index = try #require(texts.firstIndex(of: word))
            #expect(texts[safe: index + 1] == emoji)
        }
    }

    @Test func fullPinyin() async throws {
        #expect(try await first("nihao") == "你好")
        #expect(try await first("woaibeijingtiananmen") == "我爱北京天安门")
    }

    /// The Zhuyin schema reads pinyin with each syllable's tone, and the
    /// tone picks among homophones.
    @Test func tonedCodes() async throws {
        let zhuyin = RimeSchema(keyboard: .zhuyin)
        #expect(try await first("ni3hao3", schema: zhuyin) == "你好")
        #expect(try await first("shi4", schema: zhuyin) == "是")
        #expect(try await first("shi2", schema: zhuyin) == "时")
        #expect(try await first("ma1ma5", schema: zhuyin) == "妈妈")
        #expect(try await first("lv4se4", schema: zhuyin) == "绿色")
    }

    /// A user schema must survive deployment; librime trashes user copies
    /// that are older than a shared copy.
    @Test func doublePinyinSchemaIsApplied() async throws {
        #expect(try await first("nihc", schema: RimeSchema(scheme: .xiaohe)) == "你好")
        #expect(FileManager.default.fileExists(atPath: Shared.user.appendingPathComponent("sugu.schema.yaml").path))
    }

    @Test func fuzzyPinyin() async throws {
        #expect(try await first("zongguo", schema: RimeSchema(fuzzy: [.zZh])) == "中国")
    }

    @Test func traditionalScript() async throws {
        #expect(try await first("zhongguo", script: .traditional) == "中國")
    }

    @Test func japaneseKanjiForms() async throws {
        #expect(try await first("dongjing", script: .japanese) == "東京")
        #expect(try await first("hengbin", script: .japanese) == "横浜")
    }

    /// Learned words reach librime's sentences through the generated user
    /// dictionary, in full pinyin and double pinyin, and leave them when
    /// deleted from the store.
    @Test func learnedWordsJoinSentences() async throws {
        let syllables = Lexicon.load(Lexicon.syllablesFile, in: engineDataDirectory.appendingPathComponent("Lexicon"))
        let rime = engineDataDirectory.appendingPathComponent("Rime")
        func sentence(_ reading: String, words: [RimeUserDictionary.Word], schema: RimeSchema = RimeSchema()) async throws -> String? {
            try await Shared.runtime.prepare(schema, version: "test")
            let decoder = try #require(PinyinDecoder(schema: schema, syllables: syllables, sharedData: rime))
            let fullPinyin = PinyinDecoder(schema: RimeSchema(), syllables: syllables, sharedData: rime)
            try RimeUserDictionary.write(RimeUserDictionary.table(for: words, decoder: decoder, fullPinyin: fullPinyin), in: Shared.user)
            let engine = RimeEngine(runtime: Shared.runtime)
            #expect(engine.reloadUserDictionary())
            engine.insert(reading)
            defer { engine.clear() }
            return engine.state.candidates.first?.text
        }
        let typed = RimeUserDictionary.Word(reading: "suguyue", text: "苏古月", count: 1)
        #expect(try await sentence("wogensuguyueshuo", words: [typed]) == "我跟苏古月说")
        #expect(try await sentence("wogensuguyueshuo", words: []) != "我跟苏古月说")
        let doublePinyin = RimeUserDictionary.Word(reading: "suguyt", text: "苏古月", count: 1)
        #expect(try await sentence("wogfsuguytuo", words: [doublePinyin], schema: RimeSchema(scheme: .xiaohe)) == "我跟苏古月说")
        // An imported word carries full pinyin, and still types in double pinyin.
        #expect(try await sentence("wogfsuguytuo", words: [typed], schema: RimeSchema(scheme: .xiaohe)) == "我跟苏古月说")
        // A word learned in Zhuyin types in pinyin too.
        let zhuyin = RimeUserDictionary.Word(reading: "su1gu3yue4", text: "苏古月", count: 1)
        #expect(try await sentence("wogensuguyueshuo", words: [zhuyin]) == "我跟苏古月说")
        try RimeUserDictionary.write("", in: Shared.user)
    }

    /// The respelled sentence comes first; librime's own candidates follow
    /// one index further down and still highlight and commit.
    @Test func theLanguageModelRespellsLibrimesSentence() async throws {
        try await Shared.runtime.prepare(RimeSchema(), version: "test")
        let lexicon = engineDataDirectory.appendingPathComponent("Lexicon")
        let decoder = try #require(PinyinDecoder(schema: RimeSchema(), syllables: Lexicon.load(Lexicon.syllablesFile, in: lexicon), sharedData: engineDataDirectory.appendingPathComponent("Rime")))
        let words = try PinyinWords(contentsOf: lexicon.appendingPathComponent(Lexicon.pinyinWordsFile))
        let model = try testLanguageModel(["我们一起去吃晚饭吧。", "晚饭吃什么？", "今天的晚饭很好吃。"])
        let engine = RimeEngine(runtime: Shared.runtime)
        defer { engine.clear() }
        engine.insert("womenyiqiquchiwanfanba")
        let plain = try #require(engine.state.candidates.first?.text)
        #expect(plain != "我们一起去吃晚饭吧", "librime alone already writes 晚饭; pick another sentence")
        engine.clear()

        engine.respelling = .init(respeller: SentenceRespeller(model: model, words: words), decoder: decoder) { _ in nil }
        engine.insert("womenyiqiquchiwanfanba")
        #expect(engine.state.candidates.prefix(2).map(\.text) == ["我们一起去吃晚饭吧", plain])
        #expect(engine.state.highlightedIndex == 0)
        engine.highlight(1)
        #expect(engine.state.highlightedIndex == 1)
        #expect(engine.commitConverted()?.text == plain)

        engine.insert("womenyiqiquchiwanfanba")
        guard case .committed(let commit) = engine.select(0) else {
            Issue.record("selecting the respelled sentence did not commit")
            return
        }
        #expect(commit.text == "我们一起去吃晚饭吧")
        #expect(commit.reading == "womenyiqiquchiwanfanba")
        #expect(engine.state.isEmpty)
    }

    /// With fuzzy pinyin, librime may read what was typed as a derived
    /// spelling (zi for zhi); the respelling follows it.
    @Test func respellingFollowsFuzzyPinyin() async throws {
        let schema = RimeSchema(fuzzy: [.zZh, .cCh, .sSh])
        try await Shared.runtime.prepare(schema, version: "test")
        let lexicon = engineDataDirectory.appendingPathComponent("Lexicon")
        let decoder = try #require(PinyinDecoder(schema: schema, syllables: Lexicon.load(Lexicon.syllablesFile, in: lexicon), sharedData: engineDataDirectory.appendingPathComponent("Rime")))
        let words = try PinyinWords(contentsOf: lexicon.appendingPathComponent(Lexicon.pinyinWordsFile))
        let model = try testLanguageModel(["我们一起去吃晚饭吧。", "晚饭吃什么？", "今天的晚饭很好吃。"])
        let engine = RimeEngine(runtime: Shared.runtime)
        defer { engine.clear() }
        engine.respelling = .init(respeller: SentenceRespeller(model: model, words: words), decoder: decoder) { _ in nil }
        engine.insert("womenyiqiquciwanfanba")
        #expect(engine.state.candidates.first?.text == "我们一起去吃晚饭吧")
    }

    /// A Traditional sentence is respelled in Simplified; the characters
    /// that changed are converted back and the rest keep librime's forms.
    @Test func respellingKeepsTheScript() async throws {
        try await Shared.runtime.prepare(RimeSchema(), version: "test")
        let lexicon = engineDataDirectory.appendingPathComponent("Lexicon")
        let openCC = engineDataDirectory.appendingPathComponent("Rime/opencc")
        let decoder = try #require(PinyinDecoder(schema: RimeSchema(), syllables: Lexicon.load(Lexicon.syllablesFile, in: lexicon), sharedData: engineDataDirectory.appendingPathComponent("Rime")))
        let words = try PinyinWords(contentsOf: lexicon.appendingPathComponent(Lexicon.pinyinWordsFile))
        let model = try testLanguageModel(["我们一起去吃晚饭吧。", "晚饭吃什么？", "今天的晚饭很好吃。"])
        let engine = RimeEngine(runtime: Shared.runtime, script: .traditional)
        defer { engine.clear() }
        engine.respelling = .init(respeller: SentenceRespeller(model: model, words: words), decoder: decoder) { ScriptConverter.toScript($0, openCC: openCC) }
        engine.insert("womenyiqiquchiwanfanba")
        #expect(engine.state.candidates.prefix(2).map(\.text) == ["我們一起去喫晚飯吧", "我們一起去喫完飯吧"])
    }

    @Test func scriptConverterNormalizesThroughSimplified() throws {
        let openCC = engineDataDirectory.appendingPathComponent("Rime/opencc")
        let simplified = try #require(ScriptConverter.toScript(.simplified, openCC: openCC))
        #expect(simplified.convert("東京") == "东京")
        #expect(simplified.convert("横浜") == "横滨")
        let japanese = try #require(ScriptConverter.toScript(.japanese, openCC: openCC))
        #expect(japanese.convert("横滨") == "横浜")
        let traditional = try #require(ScriptConverter.toScript(.traditional, openCC: openCC))
        #expect(traditional.convert("中国") == "中國")
    }
}
