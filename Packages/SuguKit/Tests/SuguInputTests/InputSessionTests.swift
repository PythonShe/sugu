import Foundation
import Testing
import SuguCore
import SuguLearning
@testable import SuguInput

@MainActor
struct InputSessionTests {
    let source = FakeEngineSource()
    let client = FakeClient()
    let chinese = FakeEngine(table: ["nihao": ["你好", "拟好"], "shijie": ["世界"], "github": ["给他不"], "riqi": ["日期"], "nihaoshijie": ["你好世界"]])
    let japanese = FakeEngine(table: ["nihongo": ["日本語", "二本語"], "toukyou": ["東京", "東共"]], converts: true)
    let store: LearnedStore

    init() throws {
        store = try LearnedStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("sugu-session-\(UUID().uuidString)/learned.sqlite"))
        source.engines = [.chinese: chinese, .japanese: japanese]
    }

    func makeSession(_ configure: (inout Preferences) -> Void = { _ in }) -> InputSession {
        var preferences = Preferences()
        configure(&preferences)
        let latin = LatinInference(syllables: ["ni", "hao", "shi", "jie"], englishWords: ["github"])
        let session = InputSession(preferences: preferences, engines: source, store: store, modeMemory: MemoryModes(), latin: latin)
        session.attach(client)
        return session
    }

    func type(_ text: String, into session: InputSession) {
        for c in text { _ = session.handle(Key.char(c)) }
    }

    @Test func chineseComposesAndCommitsWithSpace() {
        let session = makeSession()
        type("nihao", into: session)
        #expect(client.markedText == "nihao")
        #expect(session.display.candidates?.candidates.map(\.text).prefix(2) == ["你好", "拟好"])
        #expect(session.handle(Key.space))
        #expect(client.document == "你好")
        #expect(client.marked.isEmpty)
    }

    @Test func digitsSelectAndCommitsAreLearned() {
        let session = makeSession()
        type("nihao", into: session)
        _ = session.handle(Key.char("2"))
        #expect(client.document == "拟好")
        #expect(store.lookup("nihao", mode: .chinese).map(\.text) == ["拟好"])
        // The learned word now leads the list.
        type("nihao", into: session)
        #expect(session.display.candidates?.candidates.first?.text == "拟好")
    }

    /// Letters typed while librime is set up stay in the composition and
    /// move to it once it is ready.
    @Test func lettersWaitForTheChineseEngine() {
        source.engines[.chinese] = nil
        let session = makeSession()
        #expect(source.prepared.contains(.chinese))
        type("ni", into: session)
        #expect(client.markedText == "ni")
        #expect(client.document.isEmpty)
        source.engines[.chinese] = chinese
        source.onEngineReady?(.chinese)
        #expect(client.markedText == "ni")
        type("hao", into: session)
        #expect(session.display.candidates?.candidates.first?.text == "你好")
        _ = session.handle(Key.space)
        #expect(client.document == "你好")
    }

    /// Space waits for the engine rather than committing letters; should
    /// setup fail, what was typed can still be committed.
    @Test func lettersCommitWithoutTheChineseEngine() {
        source.engines[.chinese] = nil
        let session = makeSession()
        type("ni'hao", into: session)
        #expect(session.handle(Key.space))
        #expect(client.document.isEmpty && client.markedText == "ni'hao")
        source.failing = [.chinese]
        _ = session.handle(Key.space)
        #expect(client.document == "ni'hao")
        #expect(store.lookup("ni'hao", mode: .chinese).isEmpty)
    }

    @Test func enterCommitsLetters() {
        let session = makeSession()
        type("shijie", into: session)
        _ = session.handle(Key.enter)
        #expect(client.document == "shijie")
    }

    @Test func punctuationWidthFollowsPreviousCharacter() {
        let session = makeSession()
        type("nihao", into: session)
        _ = session.handle(Key.char(","))
        #expect(client.document == "你好，")
        // Text Sugu did not type: the field is read.
        client.document += "v2"
        session.caretMayHaveMoved()
        _ = session.handle(Key.char("."))
        #expect(client.document.hasSuffix("v2."))
    }

    @Test func nonPinyinInputOffersLatinFirst() {
        let session = makeSession()
        type("github", into: session)
        #expect(session.display.candidates?.candidates.first?.text == "github")
        _ = session.handle(Key.space)
        #expect(client.document == "github")
        #expect(store.count == 0)
    }

    @Test func expressionPrefixComputes() {
        let session = makeSession()
        for c in "v12+3" { _ = session.handle(Key.char(c)) }
        #expect(session.display.candidates?.candidates.first?.text == "15")
        _ = session.handle(Key.space)
        #expect(client.document == "15")
    }

    @Test func shortcutsCommitAndPassThrough() {
        let session = makeSession()
        type("nihao", into: session)
        #expect(!session.handle(Key.commandC))
        #expect(client.document == "你好")
    }

    /// Selected Chinese text becomes a composition of the reading it was
    /// learned with, or else the dictionary's.
    @Test func selectedChineseReconverts() {
        let session = makeSession()
        source.readings = ["你好": "nihao", "世界": "shi'jie"]
        store.learn(Commit(text: "世界", reading: "shijie"), mode: .chinese)
        for (selection, reading) in [("你好", "nihao"), ("世界", "shijie")] {
            client.selection = selection
            session.reconvertSelection()
            #expect(chinese.state.reading == reading)
            session.abandonComposition()
        }
        client.selection = "Sugu"
        session.reconvertSelection()
        #expect(session.isEmpty)
    }

    /// ⇧⌫ forgets a learned candidate; on any other it is ⌫.
    @Test func shiftDeleteForgetsALearnedCandidate() {
        let session = makeSession()
        store.learn(Commit(text: "拟好", reading: "nihao"), mode: .chinese)
        _ = store.addUserWord(reading: "nihao", text: "你号", mode: .chinese)
        type("nihao", into: session)
        #expect(session.display.candidates?.candidates.prefix(2).map(\.text) == ["你号", "拟好"])
        _ = session.handle(KeyInput(keyCode: VirtualKey.tab, characters: "\t"))
        let shiftDelete = KeyInput(keyCode: VirtualKey.delete, characters: "\u{7f}", modifiers: [.shift])
        #expect(session.handle(shiftDelete))
        #expect(store.lookup("nihao", mode: .chinese).map(\.text) == ["你号"])
        #expect(session.display.candidates?.candidates.contains { $0.text == "拟好" } == false)
        #expect(client.markedText == "nihao")
        // A word the user added stays, and the key deletes.
        #expect(session.display.candidates?.candidates.first?.text == "你号")
        #expect(session.handle(shiftDelete))
        #expect(client.markedText == "niha")
        #expect(store.lookup("nihao", mode: .chinese).map(\.text) == ["你号"])
    }

    /// [ and ] commit the first or last character of the highlighted word.
    @Test func bracketsTakeACharacterOfTheWord() {
        let session = makeSession()
        type("shijie", into: session)
        type("]", into: session)
        #expect(client.document == "界")
        type("nihao", into: session)
        _ = session.handle(KeyInput(keyCode: VirtualKey.tab, characters: "\t"))
        type("[", into: session)
        #expect(client.document == "界拟")
        // Without a composition, [ is the bracket.
        type("[", into: session)
        #expect(client.document == "界拟【")
    }

    /// In Chinese, an F9/F10 form gives way when the composition is edited,
    /// and Esc goes back to the candidates rather than dropping it all.
    @Test func chineseFormsGiveWayToEditing() {
        let session = makeSession()
        let f9 = KeyInput(keyCode: VirtualKey.f9, characters: "\u{F70C}")
        type("nihao", into: session)
        _ = session.handle(f9)
        #expect(client.markedText == "ｎｉｈａｏ")
        _ = session.handle(Key.escape)
        #expect(client.markedText == "nihao")
        #expect(session.display.candidates?.candidates.first?.text == "你好")
        _ = session.handle(f9)
        _ = session.handle(Key.backspace)
        #expect(client.markedText == "niha")
        _ = session.handle(f9)
        _ = session.handle(Key.char("o"))
        #expect(client.markedText == "nihao")
        _ = session.handle(f9)
        _ = session.handle(Key.space)
        #expect(client.document == "ｎｉｈａｏ")
        type("nihao", into: session)
        _ = session.handle(f9)
        _ = session.handle(Key.char("2"))
        #expect(client.document.hasPrefix("ｎｉｈａｏｎｉｈａｏ"))
    }

    /// Keys Sugu does not bind finish the composition and reach the app.
    @Test func unboundKeysFinishTheComposition() {
        let session = makeSession()
        let f1 = KeyInput(keyCode: 122, characters: "\u{F704}")
        type("nihao", into: session)
        #expect(session.handle(Key.f7))
        #expect(client.markedText == "nihao")
        #expect(!session.handle(f1))
        #expect(client.document == "你好")
        session.setMode(.japanese)
        type("nihongo", into: session)
        #expect(!session.handle(f1))
        #expect(session.isEmpty && client.marked.isEmpty && client.document.count > 2)
    }

    /// Emacs and Kotoeri control keys edit the composition instead of
    /// committing it and reaching the app.
    @Test func controlKeysEditTheComposition() {
        let session = makeSession()
        type("nihaox", into: session)
        #expect(session.handle(Key.char("h", [.control])))
        #expect(client.markedText == "nihao")
        _ = session.handle(Key.char("n", [.control]))
        #expect(session.display.candidates?.highlightedIndex == 1)
        _ = session.handle(Key.char("p", [.control]))
        #expect(session.display.candidates?.highlightedIndex == 0)
        #expect(session.handle(Key.char("g", [.control])))
        #expect(session.isEmpty && client.document.isEmpty)
        // Without a composition they are the app's.
        #expect(!session.handle(Key.char("a", [.control])))

        session.setMode(.japanese)
        type("nihongo", into: session)
        _ = session.handle(Key.char("l", [.control]))
        #expect(client.markedText == "ｎｉｈｏｎｇｏ")
        _ = session.handle(Key.char("m", [.control]))
        #expect(client.document == "ｎｉｈｏｎｇｏ")
    }

    /// ⌃[ is Escape for vim, composing or not.
    @Test func controlBracketIsEscape() {
        let session = makeSession { $0.appRules["com.example.editor"] = AppRule(escapeSwitchesToEnglish: true) }
        #expect(!session.handle(Key.char("[", [.control])))
        #expect(session.mode == .english)
    }

    @Test func computedCandidatesAreNotLearned() throws {
        let session = makeSession()
        type("riqi", into: session)
        let row = try #require(session.display.candidates?.candidates.firstIndex { $0.source == .computed })
        session.selectCandidate(onPage: row)
        #expect(!client.document.isEmpty)
        #expect(store.count == 0)
    }

    @Test func appsCanChooseTheirChineseScript() {
        let session = makeSession { $0.appRules["com.example.editor"] = AppRule(chineseScript: .traditional) }
        #expect(source.script == .traditional)
        session.attach(FakeClient(bundleIdentifier: "com.example.other"))
        #expect(source.script == .simplified)
    }

    @Test func learnedWordsFollowTheScriptInUse() {
        store.learn(Commit(text: "東京", reading: "shijie"), mode: .chinese)
        source.conversions["東京"] = "东京"
        let session = makeSession()
        type("shijie", into: session)
        #expect(session.display.candidates?.candidates.first?.text == "东京")
        _ = session.handle(Key.space)
        #expect(client.document == "东京")
        // The use counts for the learned form; no converted twin is added.
        #expect(store.lookup("shijie", mode: .chinese).map(\.text) == ["東京"])
    }

    @Test func optionKeysTypeTheirSymbolAfterFinishingTheComposition() {
        let session = makeSession()
        #expect(!session.handle(Key.char("¥", [.option])))
        type("nihao", into: session)
        #expect(!session.handle(Key.char("…", [.option])))
        #expect(client.document == "你好")
        #expect(client.marked.isEmpty)
    }

    @Test func numpadDigitsTypeNumbersInsteadOfSelecting() {
        let session = makeSession()
        #expect(!session.handle(Key.keypad("2")))
        type("nihao", into: session)
        #expect(!session.handle(Key.keypad("2")))
        #expect(client.document == "你好")

        session.setMode(.japanese)
        type("toukyou", into: session)
        _ = session.handle(Key.space)
        _ = session.handle(Key.space)
        #expect(!session.handle(Key.keypad("1")))
        #expect(client.document == "你好東共")
    }

    @Test func numpadKeysContinueAnExpression() {
        let session = makeSession()
        type("v", into: session)
        #expect(session.handle(Key.keypad("1")))
        #expect(session.handle(Key.keypad("+")))
        #expect(session.handle(Key.keypad("2")))
        #expect(client.markedText == "v1+2")
    }

    @Test func numpadEnterCommitsTheTypedLetters() {
        let session = makeSession()
        type("nihao", into: session)
        #expect(session.handle(Key.keypadEnter))
        #expect(client.document == "nihao")
    }

    @Test func chinesePagesTurnWithPagingKeys() throws {
        chinese.table["shijie"] = ["世界", "事界", "视界", "市街", "誓戒", "时节", "使节"]
        let session = makeSession { $0.candidatesPerPage = 3 }
        type("shijie", into: session)
        let first = try #require(session.display.candidates)
        #expect(first.page == 0 && first.hasNextPage && first.highlightedIndex == 0)
        _ = session.handle(Key.char("="))
        let second = try #require(session.display.candidates)
        #expect(second.page == 1 && second.hasPreviousPage && second.highlightedIndex == 0)
        #expect(second.candidates != first.candidates)
        _ = session.handle(Key.pageUp)
        #expect(session.display.candidates?.page == 0)
        _ = session.handle(Key.pageDown)
        _ = session.handle(Key.char("-"))
        #expect(session.display.candidates?.page == 0)
        _ = session.handle(Key.pageDown)
        // Digits pick from the page on screen.
        _ = session.handle(Key.char("2"))
        #expect(client.document == second.candidates[1].text)
    }

    @Test func chineseTabAndArrowsMoveTheHighlight() throws {
        let session = makeSession()
        type("nihao", into: session)
        _ = session.handle(Key.tab)
        #expect(session.display.candidates?.highlightedIndex == 1)
        _ = session.handle(Key.shiftTab)
        #expect(session.display.candidates?.highlightedIndex == 0)
        _ = session.handle(Key.down)
        #expect(session.display.candidates?.highlightedIndex == 1)
        let chosen = try #require(session.display.candidates?.candidates[1].text)
        _ = session.handle(Key.space)
        #expect(client.document == chosen)
    }
}
