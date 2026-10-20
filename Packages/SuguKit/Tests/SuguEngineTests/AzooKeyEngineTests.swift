import Foundation
import Testing
import SuguAzooKey
import SuguCore
import SuguLM
import SuguRime

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
        engine.languageModel = try testLanguageModel(["雪が沢山降っています。", "雪が降っています。", "昨日は雪が降った。"])
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
    @Test(.enabled(if: hasEngineData)) func respellingReachesAWordJoinedToItsParticle() throws {
        let engine = try makeEngine()
        engine.insert("kanojohapianowohikimasu")
        #expect(engine.convert())
        #expect(engine.state.segments.map(\.text).joined() != "彼女はピアノを弾きます", "the converter alone already writes 弾き; pick another sentence")
        engine.clear()
        engine.languageModel = try CharacterLanguageModel(contentsOf: engineDataDirectory.appendingPathComponent("LM/ja.lm"))
        engine.insert("kanojohapianowohikimasu")
        #expect(engine.convert())
        #expect(engine.state.segments.map(\.text).joined() == "彼女はピアノを弾きます")
    }

    /// A word joined to its particle may also be written in kana when the
    /// model prefers it: the same word, so only the model decides.
    @Test(.enabled(if: hasEngineData)) func aWordJoinedToItsParticleMayBeWrittenInKana() throws {
        let engine = try makeEngine()
        engine.languageModel = try CharacterLanguageModel(contentsOf: engineDataDirectory.appendingPathComponent("LM/ja.lm"))
        engine.insert("yukigatakusanfutteimasu")
        #expect(engine.convert())
        #expect(engine.state.segments.map(\.text).joined() == "雪がたくさん降っています")
    }

    /// A conversion that is one clause takes the language model's order
    /// too, conditioned on the text before it.
    @Test(.enabled(if: hasEngineData)) func aSingleClauseIsRankedAfterTheTextBeforeIt() throws {
        let engine = try makeEngine()
        engine.languageModel = try CharacterLanguageModel(contentsOf: engineDataDirectory.appendingPathComponent("LM/ja.lm"))
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
        engine.languageModel = try testLanguageModel(["雪が沢山降っています。", "雪が降っています。", "昨日は雪が降った。"])
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
