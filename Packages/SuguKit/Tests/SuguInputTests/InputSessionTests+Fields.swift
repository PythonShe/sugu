import Foundation
import Testing
import SuguCore
import SuguLearning
@testable import SuguInput

/// Modes, apps and the field: secure input, exclusions, focus changes,
/// undo, and what Sugu reads from the field.
extension InputSessionTests {
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

    /// The shell shows a mode switched by focus less eagerly than one the
    /// user made.
    @Test func modeChangesSayWhetherTheUserMadeThem() {
        let session = makeSession()
        var changes: [(InputMode, Bool)] = []
        session.onModeChange = { changes.append(($0, $1)) }
        session.attach(FakeClient(bundleIdentifier: "com.apple.Terminal"))
        session.toggleEnglish()
        #expect(changes.map(\.0) == [.english, session.mode])
        #expect(changes.map(\.1) == [false, true])
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

    @Test func shiftTapCommitsTypedLettersThenSwitchesToEnglish() {
        let session = makeSession()
        type("hello", into: session)
        session.shiftTapped()
        #expect(client.document == "hello")
        #expect(session.mode == .english)
        session.shiftTapped()
        #expect(session.mode == .chinese)
    }

    @Test func punctuationWidthFollowsWhatWasTypedInUnreadableFields() {
        let session = makeSession()
        client.exposesText = false
        #expect(!session.handle(Key.char("3")))
        #expect(session.handle(Key.char(".")))
        #expect(client.document == ".")
        type("nihao ", into: session)
        #expect(session.handle(Key.char(",")))
        #expect(client.document == ".你好，")
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

    /// The field is read as its first composition begins, not on focus,
    /// where reading it can stall the app.
    @Test func documentVocabularyIsReadWhenTheFirstCompositionBegins() {
        let session = makeSession { $0.documentVocabulary = true }
        client.documentAfterCaret = "计划已经拟好"
        type("nihao", into: session)
        #expect(session.display.candidates?.candidates.first?.text == "拟好")
    }

    /// A password field that turns secure mid-composition gets nothing:
    /// the composition is dropped, not typed into it.
    @Test func secureInputCancelsAComposition() {
        let session = makeSession()
        type("nihao", into: session)
        session.isSecureInput = true
        #expect(session.isEmpty)
        #expect(client.marked.isEmpty)
        #expect(client.document.isEmpty)
        #expect(store.count == 0)
    }

    /// A Shift tap commits a composition with a form chosen in it as it
    /// shows, not as the letters typed.
    @Test func shiftTapCommitsAChosenFormAsShown() {
        let session = makeSession()
        type("nihao", into: session)
        _ = session.handle(KeyInput(keyCode: VirtualKey.f9, characters: "\u{F70C}"))
        let shown = client.markedText
        #expect(shown != "nihao")
        session.shiftTapped()
        #expect(client.document == shown)
        #expect(session.mode == .english)
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

    /// Terminals cannot take back what reached the shell, so ⌃⌫ is theirs.
    @Test func undoLeavesTerminalsAlone() {
        let terminal = FakeClient(bundleIdentifier: "com.apple.Terminal")
        let session = makeSession()
        session.attach(terminal)
        session.setMode(.chinese)
        for c in "nihao" { _ = session.handle(Key.char(c)) }
        _ = session.handle(Key.space)
        #expect(terminal.document == "你好")
        #expect(!session.handle(Key.undo))
        #expect(terminal.document == "你好")
    }

    /// Add Word starts from the selection and the reading Sugu knows.
    @Test func selectionBecomesAWordDraft() {
        let session = makeSession()
        source.readings = ["世界": "shi'jie"]
        client.selection = "世界"
        #expect(session.selectedWordDraft() == WordDraft(text: "世界", reading: "shijie", mode: .chinese))
        store.learn(Commit(text: "世界", reading: "shi4jie4"), mode: .chinese)
        #expect(session.selectedWordDraft().reading == "shijie")
        store.learn(Commit(text: "東京", reading: "dongjing"), mode: .chinese)
        client.selection = "東京"
        #expect(session.selectedWordDraft().reading == "dongjing")
        session.setMode(.japanese)
        client.selection = "すぐ"
        #expect(session.selectedWordDraft() == WordDraft(text: "すぐ", reading: "すぐ", mode: .japanese))
        client.selection = "直ぐ"
        #expect(session.selectedWordDraft() == WordDraft(text: "直ぐ", reading: "", mode: .japanese))
        session.setMode(.english)
        client.selection = nil
        #expect(session.selectedWordDraft() == WordDraft(text: "", reading: "", mode: .chinese))
    }
}
