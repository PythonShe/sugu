import Foundation
import Testing
import SuguAzooKey
import SuguCore
import SuguLearning
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

    /// Initials alone, and initials after full syllables, still type
    /// words while a syllable is unfinished.
    @Test func initialsTypeWordsAfterFullSyllables() async throws {
        #expect(try await first("wxq") == "微信群")
        #expect(try await first("sjk") == "数据库")
        #expect(try await first("woxq") == "我想起")
        #expect(try await first("wxiangq") == "我想起")
        #expect(try await first("woxiangzh") == "我想着")
        #expect(try await first("tamenshibs") == "他们是不是")
        try await Shared.runtime.prepare(RimeSchema(), version: "test")
        let engine = RimeEngine(runtime: Shared.runtime)
        defer { engine.clear() }
        engine.insert("woaq")
        #expect(engine.state.candidates.prefix(5).map(\.text).contains("我爱去"))
    }

    /// librime's candidates after every key of the Chinese bench and of
    /// mixed and abbreviated input, against a recorded reference: Sugu
    /// patches librime's lookup for speed (D-100), which must change no
    /// result, and a librime upgrade must not either without a look.
    /// `SUGU_RECORD_CANDIDATES=1` records the reference anew.
    @Test func librimesCandidatesMatchTheReference() async throws {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
        let reference = fixtures.appendingPathComponent("librime-candidates.txt")
        let bench = engineDataDirectory.deletingLastPathComponent().appendingPathComponent("Bench/zh.tsv")
        let sentences = try String(contentsOf: bench, encoding: .utf8).split(separator: "\n")
            .filter { !$0.hasPrefix("#") }.compactMap { $0.split(separator: "\t").first.map(String.init) }
        let probes = ["wxq", "sjk", "woxq", "wxiangq", "woaq", "woxiangzh", "woxiangchif", "tamenshibs", "chanc", "genj",
                      "zhongguor", "changanj", "xianr", "dangan", "fangan", "jiangq", "tiane", "xiane", "zgrm", "bjdx",
                      "zwdmzs", "wobuzhid", "gangang", "anan", "eee", "ng", "lve", "nvren", "xian'an", "zhonghuarenmingongheguo"]
        try RimeUserDictionary.write("", in: Shared.user)
        var lines: [String] = []
        for (name, schema) in [("default", RimeSchema()), ("fuzzy", RimeSchema(fuzzy: [.zZh, .cCh, .sSh]))] {
            try await Shared.runtime.prepare(schema, version: "test")
            let engine = RimeEngine(runtime: Shared.runtime)
            _ = engine.reloadUserDictionary()
            for input in probes + sentences {
                for key in input {
                    engine.insert(String(key))
                    lines.append("\(name)\t\(engine.state.reading)\t" + engine.state.candidates.prefix(10).map(\.text).joined(separator: " "))
                }
                engine.clear()
            }
        }
        let recorded = lines.joined(separator: "\n") + "\n"
        if ProcessInfo.processInfo.environment["SUGU_RECORD_CANDIDATES"] == "1" {
            try recorded.write(to: reference, atomically: true, encoding: .utf8)
            return
        }
        let expected = try String(contentsOf: reference, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
        let differences = zip(expected, lines).filter { $0 != $1 }
        #expect(expected.count == lines.count + 1)
        #expect(differences.isEmpty, "\(differences.count) keys differ, first: \(differences.first.map { "\($0.0) → \($0.1)" } ?? "")")
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

    /// Tables replaced under the same schema (a rime-ice update) are
    /// rebuilt once the runtime is told to deploy again.
    @Test func replacedTablesAreRebuilt() async throws {
        let folder = Shared.user.appendingPathComponent(RimeSchema.rimeIceFolder, isDirectory: true)
        let manifest = Shared.user.appendingPathComponent("\(RimeSchema.rimeIceDictionaryName).dict.yaml")
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: manifest)
        }
        func install(_ word: String, version: String) throws {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for table in RimeSchema.rimeIceTables {
                let entries = table == "base" ? "\(word)\tsu gu\t100\n" : ""
                try "---\nname: \(table)\nversion: \"\(version)\"\nsort: by_weight\n...\n\(entries)"
                    .write(to: folder.appendingPathComponent("\(table).dict.yaml"), atomically: true, encoding: .utf8)
            }
            try RimeSchema.rimeIceManifest(version: version).write(to: manifest, atomically: true, encoding: .utf8)
        }
        let schema = RimeSchema(dictionary: .rimeIce)
        try install("酥咕", version: "1")
        #expect(try await first("sugu", schema: schema) == "酥咕")

        try install("苏谷", version: "2")
        Shared.runtime.setNeedsDeployment()
        #expect(try await first("sugu", schema: schema) == "苏谷")
        _ = try await first("nihao")
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

    /// A word typed in Traditional joins Simplified sentences in Simplified
    /// and Traditional ones in Traditional: the store keeps it in
    /// Simplified, librime's dictionary's script, and librime's filters
    /// give the script in use (D-094). Kept as typed, it came out as
    /// 我去臺灣 in Simplified.
    @Test func learnedWordsJoinSentencesInTheScriptInUse() async throws {
        let store = try LearnedStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("sugu-engine-store-\(UUID().uuidString)/learned.sqlite"))
        let forms = OpenCCForms(directory: engineDataDirectory.appendingPathComponent("Rime/opencc"))
        store.chineseForms = forms
        store.learn(Commit(text: "臺灣", reading: "taiwan"), mode: .chinese, script: .traditional)
        let words = store.allWords(mode: .chinese).map { RimeUserDictionary.Word(reading: $0.reading, text: $0.text, count: $0.count) }
        #expect(words.map(\.text) == ["台湾"])

        let schema = RimeSchema()
        try await Shared.runtime.prepare(schema, version: "test")
        let syllables = Lexicon.load(Lexicon.syllablesFile, in: engineDataDirectory.appendingPathComponent("Lexicon"))
        let decoder = try #require(PinyinDecoder(schema: schema, syllables: syllables, sharedData: engineDataDirectory.appendingPathComponent("Rime")))
        try RimeUserDictionary.write(RimeUserDictionary.table(for: words, decoder: decoder, fullPinyin: nil), in: Shared.user)
        defer { try? RimeUserDictionary.write("", in: Shared.user) }
        for (script, expected) in [(ChineseScript.simplified, "我去台湾"), (.traditional, "我去臺灣")] {
            let engine = RimeEngine(runtime: Shared.runtime, script: script)
            #expect(engine.reloadUserDictionary())
            engine.insert("woqutaiwan")
            #expect(engine.state.candidates.first?.text == expected)
            engine.clear()
        }
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

    /// Words chosen one at a time are learned each under its keys, and
    /// the sentence they make is not learned as a word.
    @Test func wordsChosenOneAtATimeAreTheCommitsClauses() async throws {
        try await Shared.runtime.prepare(RimeSchema(), version: "test")
        let lexicon = engineDataDirectory.appendingPathComponent("Lexicon")
        let decoder = try #require(PinyinDecoder(schema: RimeSchema(), syllables: Lexicon.load(Lexicon.syllablesFile, in: lexicon), sharedData: engineDataDirectory.appendingPathComponent("Rime")))
        let words = try PinyinWords(contentsOf: lexicon.appendingPathComponent(Lexicon.pinyinWordsFile))
        let engine = RimeEngine(runtime: Shared.runtime)
        defer { engine.clear() }
        engine.respelling = .init(respeller: SentenceRespeller(model: try testLanguageModel(["后来去了。"]), words: words), decoder: decoder) { _ in nil }
        engine.insert("houlai'qule")
        let index = try #require(engine.state.candidates.firstIndex { $0.text == "后来" })
        #expect(engine.select(index) == .continued)
        let commit = try #require(engine.commitConverted())
        #expect(commit.text.hasPrefix("后来") && commit.text.count == 4)
        #expect(commit.clauses == [.init(reading: "houlai", text: "后来"), .init(reading: "qule", text: String(commit.text.dropFirst(2)))])
        #expect(!commit.mayBeWord)
        engine.insert("houlai")
        #expect(engine.commitConverted()?.clauses == [])
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

/// The store's conversions through OpenCC's tables, as EngineHub makes them.
@MainActor
private final class OpenCCForms: ChineseForms {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func simplified(_ text: String) -> String? {
        ScriptConverter.toScript(.simplified, openCC: directory)?.convert(text)
    }

    func text(_ text: String, in script: ChineseScript) -> String? {
        ScriptConverter.toScript(script, openCC: directory)?.convert(text)
    }
}
