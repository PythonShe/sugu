import Foundation
import Testing
import SuguCore
import SuguLearning
@testable import SuguInput

@MainActor
struct InputSessionTests {
    let provider = FakeProvider()
    let client = FakeClient()
    let chinese = FakeEngine(table: ["nihao": ["你好", "拟好"], "shijie": ["世界"], "github": ["给他不"]])
    let japanese = FakeEngine(table: ["nihongo": ["日本語", "二本語"]], converts: true)
    let store: LearnedStore

    init() throws {
        store = try LearnedStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("sugu-session-\(UUID().uuidString)/learned.sqlite"))
        provider.engines = [.chinese: chinese, .japanese: japanese]
    }

    func makeSession(_ configure: (inout Preferences) -> Void = { _ in }) -> InputSession {
        var preferences = Preferences()
        configure(&preferences)
        let latin = LatinInference(syllables: ["ni", "hao", "shi", "jie"], englishWords: ["github"])
        let session = InputSession(preferences: preferences, provider: provider, store: store, modeMemory: MemoryModes(), latin: latin)
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
        session.switchLanguage()
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
}
