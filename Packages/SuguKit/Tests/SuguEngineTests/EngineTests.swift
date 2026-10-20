import Foundation
import Testing
import SuguAzooKey
import SuguCore
import SuguLM
import SuguRime

/// End-to-end checks against the real engines and the data built by
/// `scripts/build-data.sh`. Skipped when `Data/` has not been built.
private let dataDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Data")
private let hasData = FileManager.default.fileExists(atPath: dataDirectory.appendingPathComponent("Rime/build/sugu.table.bin").path)

/// A model built from `sentences` alone.
private func languageModel(_ sentences: [String]) throws -> CharacterLanguageModel {
    var builder = CharacterLanguageModelBuilder()
    builder.minimumCount = 1
    for sentence in sentences { builder.add(sentence) }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-engine-lm-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    try builder.build().data.write(to: url)
    return try CharacterLanguageModel(contentsOf: url)
}

/// librime keeps process-wide state, so every test shares one runtime.
@MainActor
enum Shared {
    static let user = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-engine-tests-\(getpid())")
    static let runtime = RimeRuntime(directories: .init(shared: dataDirectory.appendingPathComponent("Rime"), user: user))
}

@MainActor
@Suite(.serialized, .enabled(if: hasData))
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
        let syllables = Lexicon.load(Lexicon.syllablesFile, in: dataDirectory.appendingPathComponent("Lexicon"))
        let rime = dataDirectory.appendingPathComponent("Rime")
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
        let lexicon = dataDirectory.appendingPathComponent("Lexicon")
        let decoder = try #require(PinyinDecoder(schema: RimeSchema(), syllables: Lexicon.load(Lexicon.syllablesFile, in: lexicon), sharedData: dataDirectory.appendingPathComponent("Rime")))
        let words = try PinyinWords(contentsOf: lexicon.appendingPathComponent(Lexicon.pinyinWordsFile))
        let model = try languageModel(["我们一起去吃晚饭吧。", "晚饭吃什么？", "今天的晚饭很好吃。"])
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
        let lexicon = dataDirectory.appendingPathComponent("Lexicon")
        let decoder = try #require(PinyinDecoder(schema: schema, syllables: Lexicon.load(Lexicon.syllablesFile, in: lexicon), sharedData: dataDirectory.appendingPathComponent("Rime")))
        let words = try PinyinWords(contentsOf: lexicon.appendingPathComponent(Lexicon.pinyinWordsFile))
        let model = try languageModel(["我们一起去吃晚饭吧。", "晚饭吃什么？", "今天的晚饭很好吃。"])
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
        let lexicon = dataDirectory.appendingPathComponent("Lexicon")
        let openCC = dataDirectory.appendingPathComponent("Rime/opencc")
        let decoder = try #require(PinyinDecoder(schema: RimeSchema(), syllables: Lexicon.load(Lexicon.syllablesFile, in: lexicon), sharedData: dataDirectory.appendingPathComponent("Rime")))
        let words = try PinyinWords(contentsOf: lexicon.appendingPathComponent(Lexicon.pinyinWordsFile))
        let model = try languageModel(["我们一起去吃晚饭吧。", "晚饭吃什么？", "今天的晚饭很好吃。"])
        let engine = RimeEngine(runtime: Shared.runtime, script: .traditional)
        defer { engine.clear() }
        engine.respelling = .init(respeller: SentenceRespeller(model: model, words: words), decoder: decoder) { ScriptConverter.toScript($0, openCC: openCC) }
        engine.insert("womenyiqiquchiwanfanba")
        #expect(engine.state.candidates.prefix(2).map(\.text) == ["我們一起去喫晚飯吧", "我們一起去喫完飯吧"])
    }

    @Test func scriptConverterNormalizesThroughSimplified() throws {
        let openCC = dataDirectory.appendingPathComponent("Rime/opencc")
        let simplified = try #require(ScriptConverter.toScript(.simplified, openCC: openCC))
        #expect(simplified.convert("東京") == "东京")
        #expect(simplified.convert("横浜") == "横滨")
        let japanese = try #require(ScriptConverter.toScript(.japanese, openCC: openCC))
        #expect(japanese.convert("横滨") == "横浜")
        let traditional = try #require(ScriptConverter.toScript(.traditional, openCC: openCC))
        #expect(traditional.convert("中国") == "中國")
    }
}

@MainActor
@Suite struct AzooKeyEngineTests {
    func makeEngine() throws -> AzooKeyEngine {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-azookey-tests")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        return AzooKeyEngine(configuration: .init(workingDirectory: work))
    }

    func focused(_ engine: AzooKeyEngine) -> String? {
        engine.state.segments.first { $0.role == .focused }?.text
    }

    /// A z not yet kana shows as typed, which the session's z-symbols read;
    /// the arrows are AzooKey's own.
    @Test func pendingZShowsAsTyped() throws {
        let engine = try makeEngine()
        engine.insert("kaz")
        #expect(engine.state.markedText == "かz")
        #expect(engine.state.caret == 2)
        engine.insert("h")
        #expect(engine.state.markedText == "か←")
    }

    /// Names carry their kind, which the candidate window shows.
    @Test func namesCarryTheirKind() throws {
        let engine = try makeEngine()
        engine.insert("kyouto")
        _ = engine.convert()
        let kyoto = try #require(engine.state.candidates.first { $0.text == "京都" })
        #expect(kyoto.name == .place)
        engine.clear()
        engine.insert("keiko")
        _ = engine.convert()
        #expect(engine.state.candidates.contains { $0.name == .person })
        #expect(engine.state.candidates.first { $0.text == "稽古" }?.name == nil)
        engine.clear()
    }

    @Test func firstDisplayIsBestSentence() throws {
        let engine = try makeEngine()
        engine.insert("kyouhaiitenkidesune")
        #expect(engine.state.segments.map(\.text).joined() == "きょうはいいてんきですね")
        _ = engine.convert()
        #expect(engine.state.segments.map(\.text).joined() == "今日はいい天気ですね")
        #expect(engine.state.segments.first?.role == .focused)
    }

    @Test func commitsCarryEachClauseWithItsReading() throws {
        let engine = try makeEngine()
        engine.insert("watashihagakuseidesu")
        _ = engine.convert()
        #expect(focused(engine) == "私は")
        let commit = try #require(engine.commitConverted())
        #expect(commit.text == "私は学生です")
        #expect(commit.reading == "わたしはがくせいです")
        #expect(commit.clauses.first == .init(reading: "わたしは", text: "私は"))
        #expect(commit.clauses.map(\.reading).joined() == commit.reading)
        #expect(commit.clauses.map(\.text).joined() == commit.text)
        #expect(engine.state.isEmpty)
    }

    @Test func focusMovesBetweenClauses() throws {
        let engine = try makeEngine()
        engine.insert("watashihagakuseidesu")
        _ = engine.convert()
        engine.moveFocus(forward: true)
        #expect(engine.state.segments.first?.role == .converted)
        #expect(engine.state.segments.first?.text == "私は")
        #expect(focused(engine) != nil && focused(engine) != "私は")
        engine.moveFocus(forward: false)
        #expect(focused(engine) == "私は")
    }

    @Test func resizingTheFocusKeepsTheReading() throws {
        let engine = try makeEngine()
        engine.insert("watashihagakuseidesu")
        _ = engine.convert()
        engine.resizeFocus(by: -1)
        let shorter = try #require(focused(engine))
        #expect(shorter != "私は")
        #expect(engine.state.segments.map(\.text).joined().hasPrefix(shorter))
        let commit = try #require(engine.commitConverted())
        #expect(commit.reading == "わたしはがくせいです")
        #expect(commit.clauses.map(\.reading).joined() == commit.reading)
    }

    @Test func typingDuringConversionKeepsTheFocusedClause() throws {
        let engine = try makeEngine()
        engine.insert("watashiha")
        _ = engine.convert()
        #expect(focused(engine) == "私は")
        engine.insert("ne")
        #expect(engine.state.phase == .composing)
        #expect(engine.state.segments.first?.text == "私は")
        #expect(engine.state.reading == "わたしはね")
        #expect(engine.state.typedText == "watashihane")
        let commit = try #require(engine.commitConverted())
        #expect(commit.text == "私はね")
        #expect(commit.reading == "わたしはね")
    }

    @Test func aSecondConversionKeepsTheFirstClauses() throws {
        let engine = try makeEngine()
        engine.insert("watashiha")
        _ = engine.convert()
        engine.insert("gakusei")
        _ = engine.convert()
        #expect(engine.state.segments.first == CompositionSegment("私は", role: .converted))
        #expect(focused(engine) == "学生")
        // Esc undoes only the second conversion.
        engine.cancelConversion()
        #expect(engine.state.segments.map(\.text) == ["私は", "がくせい"])
        engine.moveFocus(forward: false)
        _ = engine.convert()
        engine.moveFocus(forward: false)
        #expect(engine.state.segments.first?.text == "私は")
        let commit = try #require(engine.commitConverted())
        #expect(commit.text == "私は学生")
        #expect(commit.reading == "わたしはがくせい")
    }

    /// Choosing a clause moves on to the next clause of the best sentence,
    /// whatever the length of the one chosen.
    @Test func choosingAClauseFocusesTheNextClauseOfTheSentence() throws {
        let engine = try makeEngine()
        engine.insert("kyouhaiitenkidesune")
        #expect(engine.convert())
        let sentence = engine.state.segments.map(\.text).joined()
        #expect(sentence == "今日はいい天気ですね")
        #expect(engine.select(0) == .continued)
        #expect(engine.state.segments.map(\.text).joined() == sentence)
        #expect(focused(engine) != nil && focused(engine) != "いいて")
    }

    @Test func voicingMarksJoinTheKanaBeforeThem() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-azookey-tests")
        var configuration = AzooKeyEngine.Configuration(workingDirectory: work)
        configuration.kanaInput = true
        configuration.liveConversion = true
        let engine = AzooKeyEngine(configuration: configuration)
        for kana in ["き", "ょ", "う", "か", "゛", "あ", "゛", "は", "゜"] { engine.insert(kana) }
        engine.moveCaret(.left)
        engine.moveCaret(.right)
        #expect(engine.state.reading == "きょうがあ゛ぱ")
    }

    @Test func liveConversionShowsAndCommitsTheBestSentence() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-azookey-tests")
        var configuration = AzooKeyEngine.Configuration(workingDirectory: work)
        configuration.liveConversion = true
        let engine = AzooKeyEngine(configuration: configuration)
        engine.insert("watashihagakuseidesuk")
        #expect(engine.state.segments.map(\.text).joined() == "私は学生ですk")
        engine.deleteBackward()
        engine.moveCaret(.left)
        #expect(engine.state.segments.map(\.text).joined() == "わたしはがくせいです")
        engine.moveCaret(.end)
        let commit = try #require(engine.commitConverted())
        #expect(commit.text == "私は学生です")
        #expect(commit.reading == "わたしはがくせいです")
    }

    /// Needs a model: `SUGU_ZENZAI_MODEL=/path/to/zenz.gguf swift test`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SUGU_ZENZAI_MODEL"] != nil))
    func turningZenzaiOffReleasesTheModelBetweenCompositions() async throws {
        let model = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["SUGU_ZENZAI_MODEL"]))
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-azookey-tests")
        var configuration = AzooKeyEngine.Configuration(workingDirectory: work)
        let engine = AzooKeyEngine(configuration: configuration)
        engine.adopt(try #require(await AzooKeyEngine.loadZenzai(model, workingDirectory: work)))
        configuration.zenzaiModel = model
        engine.update(configuration)
        #expect(engine.holdsZenzai)
        engine.insert("watashi")
        configuration.zenzaiModel = nil
        engine.update(configuration)
        #expect(engine.holdsZenzai)
        engine.clear()
        #expect(!engine.holdsZenzai)
        engine.insert("watashihagakuseidesu")
        #expect(engine.convert())
        #expect(engine.state.segments.map(\.text).joined() == "私は学生です")
    }

    @Test func theLanguageModelRanksSentencesThatReadNaturally() throws {
        var builder = CharacterLanguageModelBuilder()
        builder.minimumCount = 1
        for sentence in ["雨が降りそうです。", "明日は雨が降ります。", "雪が降りそうだ。", "古い家です。"] { builder.add(sentence) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-engine-lm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try builder.build().data.write(to: url)

        let engine = try makeEngine()
        engine.insert("amegafurisoudesu")
        #expect(engine.convert())
        let plain = engine.state.segments.map(\.text).joined()
        engine.clear()
        engine.languageModel = try CharacterLanguageModel(contentsOf: url)
        engine.insert("amegafurisoudesu")
        #expect(engine.convert())
        #expect(engine.state.segments.map(\.text).joined() == "雨が降りそうです")
        #expect(plain != "雨が降りそうです", "the converter alone already ranks it first; pick another sentence")
        // The first clause is the one the ranked sentence wrote.
        #expect(engine.state.segments.first { $0.role == .focused }?.text == "雨が")
    }

    @Test func theLanguageModelRespellsAWordTheConverterDidNotPropose() throws {
        let engine = try makeEngine()
        engine.insert("yukigatakusanfutteimasu")
        #expect(engine.convert())
        let plain = engine.state.segments.map(\.text).joined()
        #expect(!plain.hasPrefix("雪が"), "the converter alone already writes 雪が; pick another sentence")
        engine.clear()
        engine.languageModel = try languageModel(["雪が沢山降っています。", "雪が降っています。", "昨日は雪が降った。"])
        engine.insert("yukigatakusanfutteimasu")
        #expect(engine.convert())
        #expect(engine.state.segments.map(\.text).joined() == "雪が沢山降っています")
        #expect(engine.state.segments.first { $0.role == .focused }?.text == "雪が")
        let commit = try #require(engine.commitConverted())
        #expect(commit.text == "雪が沢山降っています")
        #expect(commit.reading == "ゆきがたくさんふっています")
    }

    /// The converter can write a particle and the word after it as one
    /// element (を引き); the word is respelled all the same. With the
    /// bundled model, which leaves the bench's sentences out.
    @Test(.enabled(if: hasData)) func respellingReachesAWordJoinedToItsParticle() throws {
        let engine = try makeEngine()
        engine.insert("kanojohapianowohikimasu")
        #expect(engine.convert())
        #expect(engine.state.segments.map(\.text).joined() != "彼女はピアノを弾きます", "the converter alone already writes 弾き; pick another sentence")
        engine.clear()
        engine.languageModel = try CharacterLanguageModel(contentsOf: dataDirectory.appendingPathComponent("LM/ja.lm"))
        engine.insert("kanojohapianowohikimasu")
        #expect(engine.convert())
        #expect(engine.state.segments.map(\.text).joined() == "彼女はピアノを弾きます")
    }

    /// A word joined to its particle may also be written in kana when the
    /// model prefers it: the same word, so only the model decides.
    @Test(.enabled(if: hasData)) func aWordJoinedToItsParticleMayBeWrittenInKana() throws {
        let engine = try makeEngine()
        engine.languageModel = try CharacterLanguageModel(contentsOf: dataDirectory.appendingPathComponent("LM/ja.lm"))
        engine.insert("yukigatakusanfutteimasu")
        #expect(engine.convert())
        #expect(engine.state.segments.map(\.text).joined() == "雪がたくさん降っています")
    }

    /// A conversion that is one clause takes the language model's order
    /// too, conditioned on the text before it.
    @Test(.enabled(if: hasData)) func aSingleClauseIsRankedAfterTheTextBeforeIt() throws {
        let engine = try makeEngine()
        engine.languageModel = try CharacterLanguageModel(contentsOf: dataDirectory.appendingPathComponent("LM/ja.lm"))
        for (context, expected) in [("寒いのでコートを", "着ます"), ("明日の朝またここに", "来ます")] {
            engine.setLeftContext(context)
            engine.insert("kimasu")
            #expect(engine.convert())
            #expect(engine.state.segments.map(\.text).joined() == expected)
            #expect(Set(engine.state.candidates.map(\.text)).count == engine.state.candidates.count)
            engine.clear()
        }
    }

    @Test func respellingLeavesTheUsersWords() throws {
        let engine = try makeEngine()
        engine.setUserWords([(reading: "ゆき", text: "行き")])
        engine.languageModel = try languageModel(["雪が沢山降っています。", "雪が降っています。", "昨日は雪が降った。"])
        engine.insert("yukigatakusanfutteimasu")
        #expect(engine.convert())
        #expect(engine.state.segments.map(\.text).joined().hasPrefix("行きが"))
    }

    @Test func theDictionaryInMemoryKeepsTheUsersWords() async throws {
        let engine = try makeEngine()
        engine.setUserWords([(reading: "すぐ", text: "数具")])
        engine.insert("sugu")
        engine.clear()
        engine.adopt(await AzooKeyEngine.loadMemoryDictionary())
        engine.insert("sugu")
        #expect(engine.convert())
        #expect(engine.state.candidates.contains { $0.text == "数具" })
        #expect(engine.state.candidates.contains { $0.text == "直ぐ" || $0.text == "すぐ" })
    }

    @Test func cancellingAConversionThenTypingKeepsConverting() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-azookey-tests")
        var configuration = AzooKeyEngine.Configuration(workingDirectory: work)
        configuration.liveConversion = true
        let engine = AzooKeyEngine(configuration: configuration)
        for character in "sakanawoturiniikimasu" { engine.insert(String(character)) }
        #expect(engine.convert())
        engine.cancelConversion()
        #expect(engine.state.segments.map(\.text).joined() == "魚を釣りに行きます")
        engine.insert("k")
        #expect(engine.state.segments.map(\.text).joined().hasPrefix("魚を釣りに行きます"))
    }

    @Test func restoredReadingsConvertAgain() throws {
        let engine = try makeEngine()
        engine.restore(reading: "わたしはがくせいです")
        #expect(engine.state.phase == .converting)
        #expect(engine.state.segments.map(\.text).joined() == "私は学生です")
    }
}

@MainActor
@Suite struct SentenceRespellerTests {
    private let words = PinyinWords(lines: [
        "我们\two men\t500", "去\tqu\t400", "吃\tchi\t400", "完\twan\t300", "晚\twan\t200",
        "饭\tfan\t300", "吃完\tchi wan\t100", "晚饭\twan fan\t100",
    ])
    private let reading = [["wo", "men", "qu", "chi", "wan", "fan"]]

    private func respeller() throws -> SentenceRespeller {
        try SentenceRespeller(model: languageModel(["我们去吃晚饭吧。", "晚饭吃什么？", "今天的晚饭很好吃。"]), words: words)
    }

    @Test func respellsWhatTheModelReadsAsClearlyBetter() throws {
        #expect(try respeller().respelled("我们去吃完饭", readings: reading, after: "") == "我们去吃晚饭")
        #expect(try respeller().respelled("我们去吃晚饭", readings: reading, after: "") == nil)
    }

    /// One word typed after text: the text decides, by a smaller margin;
    /// alone, librime's word stands.
    @Test func aWordFollowsTheTextBeforeIt() throws {
        let words = PinyinWords(lines: ["大学\tda xue\t500", "大雪\tda xue\t300"])
        let model = try languageModel(["昨天下了一场大雪。", "今年的第一场大雪。", "他在大学学习。", "大学很大。"])
        let respeller = SentenceRespeller(model: model, words: words)
        #expect(respeller.respelled("大学", readings: [["da", "xue"]], after: "昨天晚上下了一场") == "大雪")
        #expect(respeller.respelled("大学", readings: [["da", "xue"]], after: "") == nil)
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
