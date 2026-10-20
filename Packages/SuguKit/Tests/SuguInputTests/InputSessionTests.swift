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
        client.document += "v2"
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

    @Test func undoRestoresTheLastCommit() {
        let session = makeSession()
        type("nihao", into: session)
        _ = session.handle(Key.space)
        #expect(session.handle(Key.undo))
        #expect(client.document.isEmpty)
        #expect(client.markedText == "nihao")
        // What the undone commit taught is taken back.
        #expect(store.count == 0)
        #expect(session.display.candidates != nil)
    }

    @Test func undoOnlyRightAfterTheCommit() {
        let session = makeSession()
        type("nihao", into: session)
        _ = session.handle(Key.space)
        _ = session.handle(Key.char("!"))
        #expect(!session.handle(Key.undo))
        #expect(client.document == "你好！")
    }

    @Test func modesToggleAndEnglishPassesThrough() {
        let session = makeSession()
        session.toggleEnglish()
        #expect(session.mode == .english)
        #expect(!session.handle(Key.char("n")))
        session.toggleEnglish()
        #expect(session.mode == .chinese)
        session.switchCJKMode()
        #expect(session.mode == .japanese)
    }

    @Test func terminalsStartInEnglishAndEscReturnsToEnglish() {
        let session = makeSession()
        let terminal = FakeClient(bundleIdentifier: "com.apple.Terminal")
        session.attach(terminal)
        #expect(session.mode == .english)
        session.setMode(.chinese)
        type("nihao", into: session)
        #expect(!session.handle(Key.escape))
        #expect(session.mode == .english)
        #expect(terminal.document.isEmpty)
    }

    @Test func secureInputPassesEverythingThrough() {
        let session = makeSession()
        session.isSecureInput = true
        #expect(!session.handle(Key.char("n")))
        #expect(client.marked.isEmpty)
    }

    @Test func noLearnAppsDoNotLearn() {
        let session = makeSession()
        let passwords = FakeClient(bundleIdentifier: "com.1password.1password")
        session.attach(passwords)
        type("nihao", into: session)
        _ = session.handle(Key.char("2"))
        #expect(store.count == 0)
    }

    @Test func japaneseConvertsWithSpaceAndCommitsWithEnter() {
        let session = makeSession()
        session.setMode(.japanese)
        type("nihongo", into: session)
        #expect(client.markedText == "nihongo")
        _ = session.handle(Key.space)
        #expect(client.markedText == "日本語")
        #expect(session.display.candidates == nil)
        _ = session.handle(Key.space)
        #expect(client.markedText == "二本語")
        #expect(session.display.candidates?.highlightedIndex == 1)
        _ = session.handle(Key.enter)
        #expect(client.document == "二本語")
    }

    @Test func functionKeysTransform() {
        let session = makeSession()
        session.setMode(.japanese)
        type("nihongo", into: session)
        _ = session.handle(Key.f7)
        #expect(client.markedText == "nihongo")
        _ = session.handle(KeyInput(keyCode: VirtualKey.f9, characters: "\u{F70C}"))
        #expect(client.markedText == "ｎｉｈｏｎｇｏ")
        _ = session.handle(Key.enter)
        #expect(client.document == "ｎｉｈｏｎｇｏ")
    }

    @Test func modeIsRememberedPerApp() {
        let session = makeSession()
        session.setMode(.japanese)
        let other = FakeClient(bundleIdentifier: "com.example.other")
        session.attach(other)
        session.setMode(.chinese)
        session.attach(client)
        #expect(session.mode == .japanese)
    }

    @Test func focusChangeCommitsComposition() {
        let session = makeSession()
        type("nihao", into: session)
        session.detach(client)
        #expect(client.document == "你好")
    }

    @Test func computedCandidatesAreNotLearned() throws {
        let session = makeSession()
        type("riqi", into: session)
        let row = try #require(session.display.candidates?.candidates.firstIndex { $0.source == .computed })
        session.selectCandidate(onPage: row)
        #expect(!client.document.isEmpty)
        #expect(store.count == 0)
    }

    @Test func undoLeavesTextThatChanged() {
        let session = makeSession()
        type("nihao", into: session)
        _ = session.handle(Key.space)
        client.document += "!"
        #expect(!session.handle(Key.undo))
        #expect(client.document == "你好!")
    }

    @Test func expressionsAreNotUndoable() {
        let session = makeSession()
        for c in "v12+3" { _ = session.handle(Key.char(c)) }
        _ = session.handle(Key.space)
        #expect(!session.handle(Key.undo))
        #expect(client.document == "15")
    }

    @Test func excludedAppsAreNotRead() {
        let session = makeSession { $0.noLearnApps = ["com.example.editor"] }
        client.document = "v2"
        _ = session.handle(Key.char("."))
        // Without reading "v2", punctuation cannot follow it.
        #expect(client.document == "v2。")
        _ = session.handle(Key.char("n"))
        _ = session.handle(Key.space)
        #expect(!session.handle(Key.undo))
    }

    @Test func focusChangeCommitsAPartialSelection() {
        chinese.partial["nihaoshijie"] = (5, "你好")
        chinese.table["shijie"] = ["世界"]
        let session = makeSession()
        type("nihaoshijie", into: session)
        session.detach(client)
        #expect(client.document == "你好世界")
        #expect(session.isEmpty)
    }

    @Test func japaneseOffersTypedEnglishWords() {
        let session = makeSession()
        session.setMode(.japanese)
        type("github", into: session)
        #expect(session.display.candidates?.candidates.map(\.text).contains("github") == true)
        _ = session.handle(Key.escape)
        type("nihongo", into: session)
        #expect(session.display.candidates?.candidates.contains { $0.source == .latin } != true)
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

    @Test func japaneseNamesOfferTheirChineseForm() {
        japanese.properNouns = ["東京"]
        source.conversions["東京"] = "东京"
        let session = makeSession()
        session.setMode(.japanese)
        type("toukyou", into: session)
        _ = session.handle(Key.space)
        _ = session.handle(Key.space)
        let texts = session.display.candidates?.candidates.map(\.text) ?? []
        #expect(texts.prefix(3) == ["東京", "东京", "東共"])
        // The second Space highlighted the next candidate.
        #expect(client.markedText == "东京")
        _ = session.handle(Key.enter)
        #expect(client.document == "东京")
        #expect(store.count == 0)
    }

    @Test func wordsLeftOfTheCaretRankFirst() {
        client.document = "他已经拟好了"
        let session = makeSession()
        type("nihao", into: session)
        #expect(session.display.candidates?.candidates.first?.text == "拟好")
    }

    @Test func documentVocabularyRanksWordsAnywhereInTheField() {
        client.documentAfterCaret = "计划已经拟好"
        let off = makeSession()
        type("nihao", into: off)
        #expect(off.display.candidates?.candidates.first?.text == "你好")
        off.cancelComposition()
        off.detach(client)

        let on = makeSession { $0.documentVocabulary = true }
        type("nihao", into: on)
        #expect(on.display.candidates?.candidates.first?.text == "拟好")
        #expect((source.engines[.chinese] as? FakeEngine)?.leftContext.isEmpty == true)
    }

    @Test func documentVocabularyIsNotReadInSecureInput() {
        client.documentAfterCaret = "计划已经拟好"
        let session = makeSession { $0.documentVocabulary = true }
        session.isSecureInput = true
        session.attach(client)
        session.isSecureInput = false
        type("nihao", into: session)
        #expect(session.display.candidates?.candidates.first?.text == "你好")
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
}
