import Foundation
import Testing
import SuguCore
import SuguInput
import SuguRime

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
        // A tone with no syllable to end is not taken.
        #expect(!engine.accepts("3"))
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
        // Shift-comma is the comma, after the sentence.
        _ = session.handle(KeyInput(keyCode: 0, characters: "<", modifiers: [.shift]))
        #expect(client.document == "把，")
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
