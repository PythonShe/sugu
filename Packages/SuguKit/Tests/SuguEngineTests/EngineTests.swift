import Foundation
import Testing
import SuguAzooKey
import SuguCore
import SuguRime

/// End-to-end checks against the real engines and the data built by
/// `scripts/build-data.sh`. Skipped when `Data/` has not been built.
private let dataDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Data")
private let hasData = FileManager.default.fileExists(atPath: dataDirectory.appendingPathComponent("Rime/build/sugu.table.bin").path)

/// librime keeps process-wide state, so every test shares one runtime.
@MainActor
private enum Shared {
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

    @Test func fullPinyin() async throws {
        #expect(try await first("nihao") == "你好")
        #expect(try await first("woaibeijingtiananmen") == "我爱北京天安门")
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
        try RimeUserDictionary.write("", in: Shared.user)
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

    @Test func restoredReadingsConvertAgain() throws {
        let engine = try makeEngine()
        engine.restore(reading: "わたしはがくせいです")
        #expect(engine.state.phase == .converting)
        #expect(engine.state.segments.map(\.text).joined() == "私は学生です")
    }
}
