import Foundation
import Testing
import SuguCore
import SuguLearning
@testable import SuguInput

/// Japanese composition: conversion, kana input, function and control
/// keys, retyping and symbols.
extension InputSessionTests {
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

    /// ⌃I and ⌃O shrink and grow the clause while converting; ⌃⇧R
    /// reconverts the selection.
    @Test func controlKeysOfApplesJapaneseInput() {
        let session = makeSession()
        session.setMode(.japanese)
        type("nihongo", into: session)
        let control = { (letter: String, modifiers: KeyModifiers) in
            KeyInput(keyCode: 0, characters: "", charactersIgnoringModifiers: letter, modifiers: modifiers)
        }
        #expect(session.handle(control("o", [.control])))
        #expect(japanese.resizes.isEmpty)
        _ = session.handle(Key.space)
        #expect(session.handle(control("i", [.control])))
        #expect(session.handle(control("o", [.control])))
        #expect(japanese.resizes == [-1, 1])
        _ = session.handle(Key.enter)
        client.selection = "日本語"
        #expect(session.handle(control("r", [.control, .shift])))
        #expect(!session.isEmpty)
        session.abandonComposition()
        client.selection = nil
        #expect(!session.handle(control("r", [.control, .shift])))
    }

    /// A period typed while converting commits with the conversion; a
    /// letter starts the next composition.
    @Test func periodWhileConvertingCommitsWithIt() {
        let session = makeSession()
        session.setMode(.japanese)
        japanese.acceptsSymbols = true
        type("nihongo", into: session)
        _ = session.handle(Key.space)
        type(".", into: session)
        #expect(client.document == "日本語。")
        #expect(session.isEmpty)
        type("nihongo", into: session)
        _ = session.handle(Key.space)
        type("n", into: session)
        #expect(client.document == "日本語。日本語")
        #expect(client.markedText == "n")
    }

    /// A symbol's name offers it after the engine's two best words.
    @Test func japaneseSymbolsByName() {
        let names = FakeEngine(table: ["やじるし": ["矢印", "鏃", "やじるし"]], converts: true)
        source.engines[.japanese] = names
        names.acceptsSymbols = true
        let session = makeSession()
        session.setMode(.japanese)
        type("やじるし", into: session)
        #expect(session.display.candidates?.candidates.prefix(5).map(\.text) == ["矢印", "鏃", "→", "←", "↑"])
    }

    /// F10 again cycles capitals, a capital first and lower case; F9 too.
    @Test func repeatedFunctionKeysCycleCase() {
        let session = makeSession()
        session.setMode(.japanese)
        type("nihongo", into: session)
        let f10 = KeyInput(keyCode: VirtualKey.f10, characters: "\u{F70D}")
        var shown: [String] = []
        for _ in 0..<4 {
            _ = session.handle(f10)
            shown.append(client.markedText)
        }
        #expect(shown == ["nihongo", "NIHONGO", "Nihongo", "nihongo"])
        _ = session.handle(KeyInput(keyCode: VirtualKey.f9, characters: "\u{F70C}"))
        _ = session.handle(KeyInput(keyCode: VirtualKey.f9, characters: "\u{F70C}"))
        #expect(client.markedText == "ＮＩＨＯＮＧＯ")
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

    /// 英数 twice retypes the Japanese just committed as its romaji, taking
    /// back what it taught; かな twice turns it back.
    @Test func eisuTwiceRetypesTheCommitAsRomaji() {
        let session = makeSession()
        session.setMode(.japanese)
        type("nihongo", into: session)
        _ = session.handle(Key.space)
        _ = session.handle(Key.enter)
        #expect(client.document == "日本語")
        _ = session.handle(KeyInput(keyCode: VirtualKey.eisu, characters: ""))
        #expect(session.mode == .english)
        #expect(session.retypeLastCommit(asRomaji: true))
        #expect(client.document == "nihongo")
        #expect(store.lookup("nihongo", mode: .japanese).isEmpty)
        #expect(!session.retypeLastCommit(asRomaji: true))
        _ = session.handle(KeyInput(keyCode: VirtualKey.kana, characters: ""))
        #expect(session.retypeLastCommit(asRomaji: false))
        #expect(client.document == "日本語")
        #expect(session.mode == .japanese)
    }

    @Test func retypeOnlyRightAfterTheCommit() {
        let session = makeSession()
        session.setMode(.japanese)
        type("nihongo", into: session)
        _ = session.handle(Key.space)
        _ = session.handle(Key.enter)
        _ = session.handle(Key.char("!"))
        _ = session.handle(KeyInput(keyCode: VirtualKey.eisu, characters: ""))
        #expect(!session.retypeLastCommit(asRomaji: true))
    }

    /// Terminals, fields that changed and fields Sugu may not read keep
    /// their text.
    @Test func retypeLeavesTerminalsAndChangedFieldsAlone() {
        let terminal = FakeClient(bundleIdentifier: "com.googlecode.iterm2")
        let session = makeSession()
        session.attach(terminal)
        session.setMode(.japanese)
        for c in "nihongo" { _ = session.handle(Key.char(c)) }
        _ = session.handle(Key.space)
        _ = session.handle(Key.enter)
        _ = session.handle(KeyInput(keyCode: VirtualKey.eisu, characters: ""))
        #expect(!session.retypeLastCommit(asRomaji: true))
        #expect(terminal.document == "日本語")

        session.attach(client)
        session.setMode(.japanese)
        type("nihongo", into: session)
        _ = session.handle(Key.space)
        _ = session.handle(Key.enter)
        client.document += "!"
        _ = session.handle(KeyInput(keyCode: VirtualKey.eisu, characters: ""))
        #expect(!session.retypeLastCommit(asRomaji: true))
        #expect(client.document == "日本語!")

        session.setMode(.japanese)
        type("nihongo", into: session)
        _ = session.handle(Key.space)
        _ = session.handle(Key.enter)
        client.exposesText = false
        _ = session.handle(KeyInput(keyCode: VirtualKey.eisu, characters: ""))
        #expect(!session.retypeLastCommit(asRomaji: true))
        #expect(client.document == "日本語!日本語")
    }

    /// A composition 英数 commits is retyped too.
    @Test func eisuTwiceRetypesWhatItCommitted() {
        let session = makeSession()
        session.setMode(.japanese)
        type("nihongo", into: session)
        _ = session.handle(Key.space)
        _ = session.handle(KeyInput(keyCode: VirtualKey.eisu, characters: ""))
        #expect(client.document == "日本語")
        #expect(session.retypeLastCommit(asRomaji: true))
        #expect(client.document == "nihongo")
    }

    /// かな in Japanese with text selected reconverts it.
    @Test func kanaKeyReconvertsTheSelection() {
        let session = makeSession()
        session.setMode(.japanese)
        client.selection = "にほんご"
        _ = session.handle(KeyInput(keyCode: VirtualKey.kana, characters: ""))
        #expect(japanese.state.reading == "にほんご")
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

    /// The ね and る keys' marks follow the punctuation style.
    @Test func kanaInputMarksFollowThePunctuationStyle() {
        let session = makeSession { $0.kanaInput = true; $0.japanesePunctuation = .commaPeriod }
        session.setMode(.japanese)
        japanese.acceptsSymbols = true
        for (code, character) in [(0x2B, "<"), (0x2F, ">")] as [(UInt16, String)] {
            #expect(session.handle(KeyInput(keyCode: code, characters: character, modifiers: [.shift])))
        }
        #expect(client.markedText == "，．")
    }

    /// Shift-Space types the other width of space.
    @Test func shiftSpaceTypesTheOtherWidth() {
        let session = makeSession()
        session.setMode(.japanese)
        #expect(!session.handle(Key.space))
        #expect(session.handle(KeyInput(keyCode: VirtualKey.space, characters: " ", modifiers: [.shift])))
        #expect(client.document == "　")
        var preferences = session.preferences
        preferences.fullWidthSpace = true
        session.preferences = preferences
        #expect(session.handle(Key.space))
        #expect(!session.handle(KeyInput(keyCode: VirtualKey.space, characters: " ", modifiers: [.shift])))
        #expect(client.document == "　　")
    }

    /// z and a symbol key type Google Japanese Input's symbols in romaji.
    @Test func zSymbolsInRomaji() {
        let session = makeSession()
        session.setMode(.japanese)
        type("kaz.", into: session)
        #expect(client.markedText == "ka…")
        type("z]", into: session)
        #expect(client.markedText == "ka…』")
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
