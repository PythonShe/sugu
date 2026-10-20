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

    /// Tab converts when there are no predictions to step into.
    @Test func tabConvertsWithoutPredictions() {
        let session = makeSession()
        session.setMode(.japanese)
        type("kyou", into: session)
        #expect(session.display.candidates == nil)
        _ = session.handle(Key.tab)
        #expect(japanese.state.phase == .converting)
    }

    /// かな in Japanese with text selected reconverts it.
    @Test func kanaKeyReconvertsTheSelection() {
        let session = makeSession()
        session.setMode(.japanese)
        client.selection = "にほんご"
        _ = session.handle(KeyInput(keyCode: VirtualKey.kana, characters: ""))
        #expect(japanese.state.reading == "にほんご")
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

    @Test func kanaInputTypesTheKanaOfEachKey() {
        let session = makeSession { $0.kanaInput = true }
        session.setMode(.japanese)
        japanese.acceptsSymbols = true
        // JIS places ゛ on @ and ゜ on [.
        for (code, character) in [(0x11, "t"), (0x21, "@"), (0x03, "f"), (0x1E, "[")] as [(UInt16, String)] {
            #expect(session.handle(KeyInput(keyCode: code, characters: character, isJISKeyboard: true)))
        }
        #expect(client.markedText == "か゛は゜")
    }

    @Test func kanaInputFollowsTheANSIArrangement() {
        let session = makeSession { $0.kanaInput = true }
        session.setMode(.japanese)
        japanese.acceptsSymbols = true
        for (code, character, modifiers) in [(0x27, "'", []), (0x21, "[", []), (0x1E, "}", [.shift])] as [(UInt16, String, KeyModifiers)] {
            #expect(session.handle(KeyInput(keyCode: code, characters: character, modifiers: modifiers)))
        }
        #expect(client.markedText == "け゛ー")
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

    @Test func aRevisedSelectionStaysUntilAResultIsChosen() async throws {
        let session = makeSession { $0.languageModel = .onDevice }
        let assistant = FakeAssistant()
        assistant.results = ["Hello, world", "你好，世界"]
        session.assistant = assistant
        session.setMode(.english)
        client.selection = "你好，世界"
        session.revise(selectionWith: .translate(to: .english))
        #expect(client.markedText == "你好，世界")
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.display.candidates?.candidates.map(\.text) == ["你好，世界", "Hello, world"])
        #expect(session.handle(Key.escape))
        #expect(client.document == "你好，世界")

        session.revise(selectionWith: .translate(to: .english))
        try await Task.sleep(for: .milliseconds(50))
        #expect(session.handle(Key.char("2")))
        #expect(client.document == "你好，世界Hello, world")
    }

    @Test func selectionCommandsNeedTheirLevelAndSwitch() {
        let session = makeSession { $0.languageModel = .onDevice; $0.modelForSelection = false }
        session.assistant = FakeAssistant()
        client.selection = "text"
        #expect(!session.canReviseSelection)
        let off = makeSession()
        off.assistant = FakeAssistant()
        #expect(!off.canReviseSelection)
    }

    @Test func longCompositionsGetModelCandidatesAfterTheBest() async throws {
        let session = makeSession { $0.languageModel = .onDevice; $0.modelForConversion = true; $0.modelForTranslation = true }
        let assistant = FakeAssistant()
        assistant.suggestions = CompositionSuggestions(conversions: ["你好世界！", "你好世界"], translations: [.english: "Hello world", .japanese: "こんにちは世界"])
        session.assistant = assistant
        type("nihaoshijie", into: session)
        try await Task.sleep(for: .milliseconds(700))
        #expect(assistant.requests.count == 1)
        #expect(assistant.requests.first?.translations == [.japanese, .english])
        #expect(session.display.candidates?.candidates.map(\.text).prefix(4) == ["你好世界", "你好世界！", "こんにちは世界", "Hello world"])
        session.selectCandidate(onPage: 1)
        #expect(client.document == "你好世界！")
    }

    @Test func aReadingTypedAgainBeforeThePauseIsStillAsked() async throws {
        let session = makeSession { $0.languageModel = .onDevice; $0.modelForConversion = true }
        let assistant = FakeAssistant()
        assistant.suggestions = CompositionSuggestions(conversions: ["你好世界！"])
        session.assistant = assistant
        type("nihaoshijie", into: session)
        for _ in 0..<4 { _ = session.handle(Key.backspace) }
        type("ijie", into: session)
        try await Task.sleep(for: .milliseconds(700))
        #expect(assistant.requests.count == 1)
        #expect(session.display.candidates?.candidates.map(\.text).contains("你好世界！") == true)
    }

    @Test func modelCandidatesEndWithTheirComposition() async throws {
        let session = makeSession { $0.languageModel = .onDevice; $0.modelForConversion = true }
        let assistant = FakeAssistant()
        assistant.suggestions = CompositionSuggestions(conversions: ["你好世界！"])
        session.assistant = assistant
        type("nihaoshijie", into: session)
        try await Task.sleep(for: .milliseconds(700))
        session.commitComposition()
        // The same reading elsewhere is asked again, with its own context.
        type("nihaoshijie", into: session)
        try await Task.sleep(for: .milliseconds(700))
        #expect(assistant.requests.count == 2)
        // Turned off, the model's candidates go at once.
        session.preferences.languageModel = .off
        _ = session.handle(Key.backspace)
        type("e", into: session)
        #expect(session.display.candidates?.candidates.map(\.text).contains("你好世界！") == false)
    }

    @Test func aRequestWaitingForThePauseIsDroppedWhenFocusMoves() async throws {
        let session = makeSession { $0.languageModel = .privateCloudCompute; $0.modelForConversion = true }
        let assistant = FakeAssistant()
        session.assistant = assistant
        type("nihaoshijie", into: session)
        session.attach(FakeClient(bundleIdentifier: "com.1password.1password"))
        try await Task.sleep(for: .milliseconds(700))
        #expect(assistant.requests.isEmpty)
    }

    @Test func passwordManagersNeverReachTheModel() async throws {
        let password = FakeClient(bundleIdentifier: "com.1password.1password")
        let session = makeSession { $0.languageModel = .privateCloudCompute; $0.modelForConversion = true }
        let assistant = FakeAssistant()
        session.assistant = assistant
        session.attach(password)
        for c in "nihaoshijie" { _ = session.handle(Key.char(c)) }
        try await Task.sleep(for: .milliseconds(700))
        #expect(assistant.requests.isEmpty)
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

    @Test func japaneseArrowsStepIntoPredictions() {
        let session = makeSession()
        session.setMode(.japanese)
        type("nihongo", into: session)
        #expect(session.display.candidates?.highlightedIndex == nil)
        _ = session.handle(Key.down)
        #expect(session.display.candidates?.highlightedIndex == 0)
        #expect(client.markedText == "日本語")
        _ = session.handle(Key.up)
        #expect(session.display.candidates?.highlightedIndex == 0)
        _ = session.handle(Key.enter)
        #expect(client.document == "日本語")
    }

    @Test func japaneseEscapeStepsBackOutOfConversion() {
        let session = makeSession()
        session.setMode(.japanese)
        type("nihongo", into: session)
        _ = session.handle(Key.space)
        #expect(client.markedText == "日本語")
        _ = session.handle(Key.escape)
        #expect(client.markedText == "nihongo")
        _ = session.handle(Key.escape)
        #expect(client.marked.isEmpty)
        #expect(client.document.isEmpty)
    }

    @Test func japaneseBackspaceLeavesConversionBeforeDeleting() {
        let session = makeSession()
        session.setMode(.japanese)
        type("nihongo", into: session)
        _ = session.handle(Key.space)
        _ = session.handle(Key.backspace)
        #expect(client.markedText == "nihongo")
        _ = session.handle(Key.backspace)
        #expect(client.markedText == "nihong")
    }
}
