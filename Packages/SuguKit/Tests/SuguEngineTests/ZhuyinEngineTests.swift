import Foundation
import Testing
import SuguCore
import SuguInput
@testable import SuguRime

/// Zhuyin shares the suite's librime runtime, so its tests run in turn
/// with the other librime tests.
extension RimeEngineTests {
    private func zhuyin() async throws -> ZhuyinEngine {
        try await Shared.runtime.prepare(RimeSchema(keyboard: .zhuyin), version: "test")
        return ZhuyinEngine(runtime: Shared.runtime)
    }

    /// ㄋㄧˇ ㄏㄠˇ on the standard layout.
    private static let nihao = "su3cl3"

    @Test func zhuyinConvertsAsSyllablesEnd() async throws {
        let engine = try await zhuyin()
        engine.insert("su")
        #expect(engine.state.segments == [CompositionSegment("ㄋㄧ", role: .input)])
        engine.insert("3")
        #expect(engine.state.markedText == "你")
        engine.insert("cl3")
        #expect(engine.state.markedText == "你好")
        #expect(engine.state.reading == "ni3hao3")
        // Space with no syllable to end is not a tone.
        #expect(!engine.accepts(" "))
        let commit = try #require(engine.commitConverted())
        #expect(commit.text == "你好")
        #expect(commit.reading == "ni3hao3")
        #expect(engine.state.isEmpty)
    }

    @Test func zhuyinBackspaceTakesSymbolsThenSyllables() async throws {
        let engine = try await zhuyin()
        engine.insert(Self.nihao + "a8")
        #expect(engine.state.markedText == "你好ㄇㄚ")
        engine.deleteBackward()
        #expect(engine.state.markedText == "你好ㄇ")
        engine.deleteBackward()
        engine.deleteBackward()
        #expect(engine.state.markedText == "你")
        engine.clear()
    }

    /// A word chosen at the caret stays while syllables are typed around it.
    @Test func zhuyinChoiceStays() async throws {
        let engine = try await zhuyin()
        engine.insert("g4")
        #expect(engine.convert())
        #expect(engine.state.phase == .converting)
        let texts = engine.state.candidates.map(\.text)
        let index = try #require(texts.firstIndex(of: "事"))
        #expect(texts.first == engine.state.markedText || engine.state.highlightedIndex == 0)
        #expect(engine.select(index) == .continued)
        #expect(engine.state.phase == .composing)
        #expect(engine.state.markedText == "事")
        engine.insert("fu/6")
        #expect(engine.state.markedText.hasPrefix("事"))
        let commit = try #require(engine.commitConverted())
        #expect(commit.clauses == [Commit.Clause(reading: "shi4", text: "事")])
    }

    /// The window offers words ending at the caret, the longest first, and
    /// choosing one replaces those syllables.
    @Test func zhuyinWordsEndAtTheCaret() async throws {
        let engine = try await zhuyin()
        engine.insert(Self.nihao)
        #expect(engine.convert())
        let candidates = engine.state.candidates.map(\.text)
        #expect(candidates.first == "你好")
        #expect(candidates.contains("好"))
        engine.moveCaret(.left)
        #expect(engine.convert())
        #expect(engine.state.candidates.first?.text == "你")
        engine.clear()
    }

    /// With no syllable pending, a tone changes the one before the caret.
    @Test func zhuyinToneRetonesTheLastSyllable() async throws {
        let engine = try await zhuyin()
        engine.insert("a8 ")
        #expect(engine.state.reading == "ma1")
        #expect(engine.accepts("3"))
        #expect(!engine.accepts(" "))
        engine.insert("3")
        #expect(engine.state.reading == "ma3")
        #expect(engine.state.markedText == "马")
        engine.clear()
    }

    /// A sentence past its length commits its start and composes on.
    @Test func zhuyinLetsGoOfALongSentencesStart() async throws {
        let engine = try await zhuyin()
        engine.insert(String(repeating: "a8 ", count: ZhuyinEngine.longestSentence))
        #expect(engine.takeOverflow() == nil)
        engine.insert(Self.nihao)
        let head = try #require(engine.takeOverflow())
        #expect(head.reading == "ma1ma1")
        #expect(!head.mayBeWord)
        #expect(head.text.count == 2)
        #expect(engine.takeOverflow() == nil)
        #expect(engine.state.reading.hasSuffix("ni3hao3"))
        #expect(engine.state.markedText.hasSuffix("你好"))
        engine.clear()
    }

    /// Punctuation stays in the sentence and splits it; words stop at it.
    @Test func zhuyinKeepsLiteralsInTheSentence() async throws {
        let engine = try await zhuyin()
        engine.insert(Self.nihao)
        #expect(engine.insertLiteral("，"))
        #expect(!engine.convert())
        engine.insert("a8 ")
        #expect(engine.state.markedText == "你好，妈")
        #expect(engine.convert())
        #expect(engine.state.candidates.allSatisfy { $0.text.count == 1 })
        engine.cancelConversion()
        let commit = try #require(engine.commitConverted())
        #expect(commit.text == "你好，妈")
        #expect(commit.reading == "ni3hao3，ma1")
        #expect(!commit.mayBeWord)
        // A commit taken back comes back with its literal.
        engine.restore(reading: commit.reading)
        #expect(engine.state.markedText == "你好，妈")
        engine.clear()
    }

    /// A literal ends the half-typed syllable with the first tone.
    @Test func zhuyinLiteralEndsThePendingSyllable() async throws {
        let engine = try await zhuyin()
        engine.insert("a8")
        #expect(engine.insertLiteral("A"))
        #expect(engine.state.markedText == "妈A")
        engine.deleteBackward()
        #expect(engine.state.markedText == "妈")
        engine.clear()
    }

    /// The start let go of as the last syllable ends goes with the commit.
    @Test func zhuyinCommitKeepsTheStartLetGoOfLast() async throws {
        let engine = try await zhuyin()
        engine.insert(String(repeating: "a8 ", count: ZhuyinEngine.longestSentence) + "a8")
        let commit = try #require(engine.commitConverted())
        #expect(commit.text.count == ZhuyinEngine.longestSentence + 1)
        #expect(commit.reading == String(repeating: "ma1", count: ZhuyinEngine.longestSentence + 1))
        #expect(engine.takeOverflow() == nil)
    }

    @Test func zhuyinRestoresItsReading() async throws {
        let engine = try await zhuyin()
        engine.restore(reading: "ni3hao3")
        #expect(engine.state.markedText == "你好")
        engine.clear()
        engine.restore(reading: "nihao")
        #expect(engine.state.isEmpty)
    }

    // MARK: Through the input session

    private func session() async throws -> (InputSession, ZhuyinClient) {
        let source = ZhuyinSource(engine: try await zhuyin())
        var preferences = Preferences()
        preferences.chineseKeyboard = .zhuyin
        let session = InputSession(preferences: preferences, engines: source, store: nil)
        let client = ZhuyinClient()
        session.attach(client)
        session.setMode(.chinese)
        return (session, client)
    }

    private func type(_ keys: String, into session: InputSession) {
        for character in keys {
            let code = character == " " ? VirtualKey.space : 0
            _ = session.handle(KeyInput(keyCode: code, characters: String(character)))
        }
    }

    @Test func zhuyinSessionSpaceIsTheFirstTone() async throws {
        let (session, client) = try await session()
        // ㄇㄚ then Space: 妈, the first tone.
        type("a8 ", into: session)
        #expect(client.marked == "妈")
        #expect(session.display.candidates == nil)
        // Space between syllables opens the window; a digit chooses.
        type(" ", into: session)
        let shown = try #require(session.display.candidates)
        let row = try #require(shown.candidates.firstIndex { $0.text == "妈" })
        type(String(row + 1), into: session)
        #expect(session.display.candidates == nil)
        #expect(client.marked == "妈")
        _ = session.handle(KeyInput(keyCode: VirtualKey.returnKey, characters: "\r"))
        #expect(client.document == "妈")
    }

    @Test func zhuyinSessionDigitsAreSymbols() async throws {
        let (session, client) = try await session()
        // ㄅ is 1 and ㄚ is 8; 3 is the third tone.
        type("183", into: session)
        #expect(client.marked == "把")
        // Shift-comma is the comma, in the sentence.
        _ = session.handle(KeyInput(keyCode: 0, characters: "<", modifiers: [.shift]))
        #expect(client.marked == "把，")
    }

    @Test func zhuyinSessionStartsOnlyOnZhuyinKeys() async throws {
        let (session, client) = try await session()
        #expect(!session.handle(KeyInput(keyCode: 0, characters: "3")))
        #expect(!session.handle(KeyInput(keyCode: VirtualKey.space, characters: " ")))
        #expect(session.handle(KeyInput(keyCode: 0, characters: "1")))
        #expect(client.marked == "ㄅ")
        _ = session.handle(KeyInput(keyCode: VirtualKey.escape, characters: "\u{1B}"))
        #expect(client.marked.isEmpty)
        #expect(client.document.isEmpty)
    }

    /// Esc takes the half-typed syllable, then the sentence.
    @Test func zhuyinSessionEscapeTakesThePendingSyllableFirst() async throws {
        let (session, client) = try await session()
        type(Self.nihao + "a8", into: session)
        #expect(client.marked == "你好ㄇㄚ")
        _ = session.handle(KeyInput(keyCode: VirtualKey.escape, characters: "\u{1B}"))
        #expect(client.marked == "你好")
        _ = session.handle(KeyInput(keyCode: VirtualKey.escape, characters: "\u{1B}"))
        #expect(client.marked.isEmpty)
        #expect(client.document.isEmpty)
    }

    @Test func zhuyinSessionKeepsPunctuationAndLettersInTheSentence() async throws {
        let (session, client) = try await session()
        type(Self.nihao, into: session)
        _ = session.handle(KeyInput(keyCode: 0, characters: "<", modifiers: [.shift]))
        _ = session.handle(KeyInput(keyCode: 0, characters: "A", modifiers: [.shift]))
        #expect(client.marked == "你好，A")
        #expect(client.document.isEmpty)
        _ = session.handle(KeyInput(keyCode: VirtualKey.returnKey, characters: "\r"))
        #expect(client.document == "你好，A")
    }

    @Test func zhuyinSessionCommitsTheStartOfALongSentence() async throws {
        let (session, client) = try await session()
        type(String(repeating: "a8 ", count: ZhuyinEngine.longestSentence + 1), into: session)
        #expect(client.document.count == 1)
        #expect(client.marked.count == ZhuyinEngine.longestSentence)
        _ = session.handle(KeyInput(keyCode: VirtualKey.returnKey, characters: "\r"))
        #expect(client.document.count == ZhuyinEngine.longestSentence + 1)
    }
}

@MainActor
private final class ZhuyinSource: EngineSource {
    let engine: ZhuyinEngine
    var onEngineReady: ((InputMode) -> Void)?

    init(engine: ZhuyinEngine) { self.engine = engine }

    func engine(for mode: InputMode) -> (any CompositionEngine)? { mode == .chinese ? engine : nil }
    func prepare(_ mode: InputMode) {}
    func isFailing(_ mode: InputMode) -> Bool { false }
    func learnedWordsDidChange() {}
    func setChineseScript(_ script: ChineseScript) {}
    func chineseText(_ text: String) -> String? { text }
    func chineseReading(of text: String) -> String? { nil }
}

@MainActor
private final class ZhuyinClient: InputClient {
    var bundleIdentifier: String? = "com.example.editor"
    var document = ""
    var marked = ""

    func commit(_ text: String) {
        document += text
        marked = ""
    }

    func setMarkedText(_ segments: [CompositionSegment], caret: Int) { marked = segments.map(\.text).joined() }
    func textBeforeCaret(limit: Int) -> String? { String(document.suffix(limit)) }
    func textAfterCaret(limit: Int) -> String? { "" }
    func deleteBeforeCaret(count: Int) -> Bool { false }
    func selectedText() -> String? { nil }
}

extension RimeEngineTests {
    /// Symbols that end no syllable are committed as written.
    @Test func zhuyinKeepsAnUnfinishedSyllable() async throws {
        try await Shared.runtime.prepare(RimeSchema(keyboard: .zhuyin), version: "test")
        let engine = ZhuyinEngine(runtime: Shared.runtime)
        engine.insert("su3c")
        let commit = try #require(engine.commitConverted())
        #expect(commit.text == "你ㄏ")
        #expect(commit.reading == commit.text)
    }
}

extension RimeEngineTests {
    /// Words learned in Zhuyin take part in its sentences; pinyin's, which
    /// have no tones, are left out.
    @Test func zhuyinLearnedWordsJoinSentences() async throws {
        try await Shared.runtime.prepare(RimeSchema(keyboard: .zhuyin), version: "test")
        let decoder = PinyinDecoder(syllables: [], rules: [])
        let words = [RimeUserDictionary.Word(reading: "su1gu3yue4", text: "苏古悦", count: 1), RimeUserDictionary.Word(reading: "nihao", text: "拟好", count: 9)]
        let table = RimeUserDictionary.table(for: words, decoder: decoder, fullPinyin: nil, keyboard: .zhuyin)
        #expect(table.contains("苏古悦\tsū gǔ yuè"))
        #expect(!table.contains("拟好"))
        let engine = ZhuyinEngine(runtime: Shared.runtime)
        try RimeUserDictionary.write("", in: Shared.user)
        #expect(engine.reloadUserDictionary())
        engine.insert("nj ej3m,4")
        #expect(engine.state.markedText != "苏古悦")
        engine.clear()
        try RimeUserDictionary.write(table, in: Shared.user)
        defer { try? RimeUserDictionary.write("", in: Shared.user) }
        #expect(engine.reloadUserDictionary())
        // ㄙㄨ ㄍㄨˇ ㄩㄝˋ
        engine.insert("nj ej3m,4")
        #expect(engine.state.markedText == "苏古悦")
        engine.clear()
    }
}

extension RimeEngineTests {
    @Test func zhuyinFindsTheTonesOfText() async throws {
        try await Shared.runtime.prepare(RimeSchema(keyboard: .zhuyin), version: "test")
        let engine = ZhuyinEngine(runtime: Shared.runtime)
        #expect(engine.codes(typing: "你好", readAs: ["ni", "hao"]) == "ni3hao3")
        #expect(engine.codes(typing: "妈妈", readAs: ["ma", "ma"]) == "ma1ma1")
        let codes = try #require(engine.codes(typing: "我们去看电影", readAs: ["wo", "men", "qu", "kan", "dian", "ying"]))
        engine.restore(reading: codes)
        #expect(engine.state.markedText == "我们去看电影")
        engine.clear()
    }
}

extension RimeEngineTests {
    /// Words keep their neutral tones.
    @Test func zhuyinFindsTheTonesOfWords() async throws {
        try await Shared.runtime.prepare(RimeSchema(keyboard: .zhuyin), version: "test")
        let engine = ZhuyinEngine(runtime: Shared.runtime)
        #expect(engine.codes(typing: "谢谢你", readAs: ["xie", "xie", "ni"]) == "xie4xie5ni3")
        #expect(engine.codes(typing: "衣服", readAs: ["yi", "fu"]) == "yi1fu5")
    }
}
