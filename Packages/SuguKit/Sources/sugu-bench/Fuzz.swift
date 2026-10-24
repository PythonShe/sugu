import Darwin
import Foundation
import SuguCore
import SuguEngines
import SuguInput
import SuguLearning

/// Random key sequences through `InputSession` with the real engines,
/// checking after every key what must hold whatever was typed. Each
/// session follows from the seed and its number, so a failure replays with
/// `--fuzz-session`.
@MainActor
enum Fuzz {
    struct Failure: Error, CustomStringConvertible {
        var mode: InputMode
        var session: Int
        var keys: [String]
        var problem: String

        var description: String {
            "\(mode) session \(session): \(problem)\n  keys: \(keys.joined(separator: " "))"
        }
    }

    /// With `trace`, every key and the composition before it go to
    /// standard error. With `soak`, the memory in use is printed every
    /// `soak` sessions, and between sessions the main queue and run loop
    /// run and autoreleased objects go, as between events in the app. With
    /// `failedDeploy`, librime has no data, so every deployment fails.
    /// Sessions that change settings or pause depend on how long engines
    /// take to set up, so they may not replay exactly.
    static func run(data: URL, sessions: Range<Int>, seed: UInt64, trace: Bool, soak: Int? = nil, failedDeploy: Bool = false, configure: (inout Preferences) -> Void) async throws -> [Failure] {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-fuzz-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        var preferences = Preferences()
        preferences.rememberModePerApp = false
        configure(&preferences)
        let lexicon = data.appendingPathComponent("Lexicon")
        let rime = failedDeploy ? work.appendingPathComponent("NoRime") : data.appendingPathComponent("Rime")
        try FileManager.default.createDirectory(at: rime, withIntermediateDirectories: true)
        let syllables = Lexicon.load(Lexicon.syllablesFile, in: lexicon)
        let store = try LearnedStore(url: work.appendingPathComponent("learned.sqlite"), syllabary: PinyinSyllabary(syllables))
        let engines = EngineHub(
            locations: EngineHub.Locations(
                rimeShared: rime,
                rimeUser: work.appendingPathComponent("Rime"),
                azooKey: work.appendingPathComponent("AzooKey"),
                models: work.appendingPathComponent("Models"),
                lexicon: lexicon,
                languageModels: data.appendingPathComponent("LM")
            ),
            preferences: preferences,
            store: store,
            version: "fuzz",
            chineseWordsDelay: .zero
        )
        await engines.waitUntilReady()
        engines.prepare(.japanese)
        let latin = LatinInference(syllables: syllables, englishWords: Lexicon.load(Lexicon.englishWordsFile, in: lexicon))
        let session = InputSession(preferences: preferences, engines: engines, store: store, latin: latin)
        // Focus moves between two fields of different apps.
        let fields = [FuzzField(bundleIdentifier: "com.zheng-she.sugu-fuzz"), FuzzField(bundleIdentifier: "com.zheng-she.sugu-fuzz.other")]
        var focused = 0
        var field: FuzzField { fields[focused] }
        session.attach(field)

        var failures: [Failure] = []
        for mode in [InputMode.chinese, .japanese] {
            for number in sessions {
                // Each session starts from the settings of the run, in the
                // first field, typing hiragana, in its own language.
                session.isSecureInput = false
                if session.preferences != preferences {
                    engines.apply(preferences)
                    session.preferences = preferences
                    await engines.waitUntilReady()
                }
                if focused != 0 {
                    session.detach(field)
                    focused = 0
                    session.attach(field)
                }
                if session.typesKatakana { session.setKatakana(false) }
                session.setMode(mode)
                // Where a trap stopped the run.
                FileHandle.standardError.write(Data("fuzz \(mode) \(number)\n".utf8))
                var random = SplitMix(seed: seed &+ UInt64(number) &* 0x9E37_79B9)
                var keys: [String] = []
                func fail(_ problem: String) -> Failure { Failure(mode: mode, session: number, keys: keys, problem: problem) }
                fields.forEach { $0.reset() }
                // Whether Zhuyin is composing now; a session may switch
                // languages and keyboards.
                var zhuyin: Bool { session.mode == .chinese && session.preferences.chineseKeyboard == .zhuyin }
                do {
                    for _ in 0..<random.next(below: 60) + 5 {
                        let layout = session.preferences.chineseKeyboard == .zhuyin ? session.preferences.zhuyinLayout : nil
                        let (name, action) = randomAction(&random, mode: mode, zhuyin: mode == .chinese ? layout : nil)
                        let previous = keys.last
                        keys.append(name)
                        if trace { FileHandle.standardError.write(Data("  \(name) → \(session.display.segments.map(\.text).joined())\n".utf8)) }
                        // In Zhuyin, Return in the candidate window takes the
                        // highlighted word; the next commits.
                        let wasComposing = !session.display.segments.isEmpty && !(zhuyin && session.display.candidates != nil)
                        let committed = field.committed
                        let key: KeyInput
                        switch action {
                        case .key(let pressed): key = pressed
                        case .shiftTap: session.shiftTapped(); try check(session, field, fail); continue
                        case .switchLanguage: session.switchCJKMode(); try check(session, field, fail); continue
                        case .click: field.click(); session.caretMayHaveMoved(); try check(session, field, fail); continue
                        case .switchField:
                            let left = field
                            session.detach(left)
                            focused = 1 - focused
                            session.attach(field)
                            guard left.marked.isEmpty else { throw fail("the field left still shows a composition") }
                            try check(session, field, fail)
                            continue
                        case .changeSetting(let change):
                            var changed = session.preferences
                            change(&changed)
                            // In the order the app applies them.
                            engines.apply(changed)
                            session.preferences = changed
                            try check(session, field, fail)
                            continue
                        case .pause(let duration):
                            try? await Task.sleep(for: duration)
                            try check(session, field, fail)
                            continue
                        case .changeWords(let change):
                            change(store)
                            engines.learnedWordsDidChange()
                            try check(session, field, fail)
                            continue
                        case .select(let count): field.select(last: count); try check(session, field, fail); continue
                        case .secureInput: session.isSecureInput.toggle(); try check(session, field, fail); continue
                        case .retryChinese: engines.retryChinese(); try check(session, field, fail); continue
                        }
                        // 英数 or かな twice retypes the last commit, as the
                        // shell checks before the session has the key.
                        if name == previous, key.keyCode == VirtualKey.eisu || key.keyCode == VirtualKey.kana,
                           session.retypeLastCommit(asRomaji: key.keyCode == VirtualKey.eisu) {
                            try check(session, field, fail)
                            continue
                        }
                        if !session.handle(key) { field.typeUnhandled(key) }
                        try check(session, field, fail)
                        if key.keyCode == VirtualKey.returnKey, key.modifiers.isEmpty, wasComposing {
                            guard session.display.segments.isEmpty else { throw fail("Return left a composition") }
                            guard field.committed.count > committed.count else { throw fail("Return committed nothing") }
                        }
                    }
                    if zhuyin, session.display.candidates != nil {
                        keys.append("⏎")
                        _ = session.handle(KeyInput(keyCode: VirtualKey.returnKey, characters: "\r"))
                        try check(session, field, fail)
                    }
                    keys.append("⏎")
                    let wasComposing = !session.display.segments.isEmpty
                    _ = session.handle(KeyInput(keyCode: VirtualKey.returnKey, characters: "\r"))
                    try check(session, field, fail)
                    if wasComposing, !session.display.segments.isEmpty { throw fail("Return left a composition") }
                } catch let failure as Failure {
                    failures.append(failure)
                    session.commitComposition()
                }
                if let soak {
                    autoreleasepool { _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001)) }
                    await Task.yield()
                    if (number + 1) % soak == 0 {
                        let memory = Memory.current()
                        print(String(format: "soak %@ %d: footprint %.1f MB, resident %.1f MB", "\(mode)", number + 1, memory.footprintMB, memory.residentMB))
                        // Shown as it happens when the output goes to a file.
                        fflush(stdout)
                    }
                }
            }
        }
        return failures
    }

    /// What holds after any key.
    private static func check(_ session: InputSession, _ field: FuzzField, _ fail: (String) -> Failure) throws {
        let display = session.display
        let length = display.segments.map(\.text.count).reduce(0, +)
        guard (0...length).contains(display.caret) else { throw fail("caret \(display.caret) outside \(length) characters") }
        if display.segments.contains(where: \.text.isEmpty) { throw fail("an empty segment") }
        guard field.marked.map(\.text).joined() == display.segments.map(\.text).joined() else {
            throw fail("the field shows \"\(field.marked.map(\.text).joined())\", the session \"\(display.segments.map(\.text).joined())\"")
        }
        if let page = display.candidates {
            if page.candidates.isEmpty { throw fail("an empty candidate page") }
            if let row = page.highlightedIndex, !page.candidates.indices.contains(row) { throw fail("highlight \(row) outside \(page.candidates.count) rows") }
            if page.candidates.contains(where: \.text.isEmpty) { throw fail("an empty candidate") }
        }
    }

    private static let japaneseSyllables = "a i u e o ka ki ku ke ko sa shi su se so ta chi tsu te to na ni nu ne no ha hi fu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wo n nn ga gi gu ge go za ji zu ze zo da de do ba bi bu be bo pa pi pu pe po kya kyu kyo sha shu sho cha chu cho ryo tt kk xtu -".split(separator: " ")
    private static let pinyinSyllables = "a o e ai ei ao ou an en ang eng er ba bo bai bei bao ban ben bang beng bi bie biao bian bin bing bu ca ce cai cao can cang ci cu cha che chi chu chuan da de dai dao dan dang deng di dian ding du dui duo fa fo fei fan fen fang feng fu ga ge gai gao gan gen gang gong gu gua guo ha he hai hao han hen hang hong hu hua huo ji jia jie jian jin jing ju jue ka ke kai kan kang kong ku kuai la le lai lao lan lang li lian liang lin ling lu lv lve ma me mai mao man men mang mi mian ming mu na ne nai nan nen ni nian nin nu nv pa po pai pao pan pen pi pian pin ping pu qi qia qian qin qing qu quan ran ren ri rou ru sa se san sen si su shi shang shen sheng shu ta te tai tan tang ti tian ting tu tong wa wo wai wan wen wang wu xi xia xian xin xing xu xue ya ye yao yan yin ying yong yu yuan za ze zai zan zi zu zhi zhang zhe zheng zhong zhu '".split(separator: " ")

    /// A Zhuyin layout's symbol keys and its tone keys other than Space.
    private static func zhuyinKeys(_ layout: ZhuyinLayout) -> (symbols: [Character], tones: [Character]) {
        let keys = Zhuyin.standardKeys(for: layout)
        return (keys.filter { Zhuyin.keyboard[$0.value] != nil }.keys.sorted(), keys.filter { $0.key != " " && Zhuyin.toneKeys[$0.value] != nil }.keys.sorted())
    }

    enum Action {
        case key(KeyInput)
        /// Shift pressed and released alone: English and back.
        case shiftTap
        /// Chinese ↔ Japanese.
        case switchLanguage
        /// The caret moved by a click.
        case click
        /// Focus moved to the other field.
        case switchField
        /// A setting changed, as in the Settings window.
        case changeSetting((inout Preferences) -> Void)
        /// Time passed between keys, while engines are being set up.
        case pause(Duration)
        /// Learned words changed elsewhere: an import, a sync, the Settings
        /// window.
        case changeWords((LearnedStore) -> Void)
        /// The last characters typed were selected.
        case select(Int)
        /// Secure input turned on or off.
        case secureInput
        /// Chinese setup tried again, as from Settings.
        case retryChinese
    }

    /// What a person might do while composing, with its name for the
    /// failure report.
    private static func randomAction(_ random: inout SplitMix, mode: InputMode, zhuyin: ZhuyinLayout?) -> (String, Action) {
        switch random.next(below: 1000) {
        case 0..<10: return ("⇧tap", .shiftTap)
        case 10..<15: return ("⌃␣", .switchLanguage)
        case 15..<20: return ("click", .click)
        case 20..<24: return ("focus", .switchField)
        case 24..<28:
            let (name, change) = randomSetting(&random)
            return ("set \(name)", .changeSetting(change))
        case 28..<31:
            let milliseconds = 1 + random.next(below: 50)
            return ("wait \(milliseconds)ms", .pause(.milliseconds(milliseconds)))
        case 31..<34:
            let (name, change) = randomWordsChange(&random, mode: mode)
            return ("words \(name)", .changeWords(change))
        case 34..<38:
            let count = 1 + random.next(below: 4)
            return ("select \(count)", .select(count))
        case 38..<40: return ("secure", .secureInput)
        case 40..<41: return ("retry", .retryChinese)
        default:
            let (name, key) = randomKey(&random, mode: mode, zhuyin: zhuyin)
            return (name, .key(key))
        }
    }

    /// A setting someone might change while typing.
    private static func randomSetting(_ random: inout SplitMix) -> (String, (inout Preferences) -> Void) {
        func pick<T: CaseIterable>(_ type: T.Type) -> T {
            let cases = Array(T.allCases)
            return cases[random.next(below: cases.count)]
        }
        switch random.next(below: 12) {
        case 0:
            let script = pick(ChineseScript.self)
            return ("script \(script)", { $0.chineseScript = script })
        case 1:
            let size = 5 + random.next(below: 6)
            return ("page \(size)", { $0.candidatesPerPage = size })
        case 2:
            let layout = pick(CandidateLayout.self)
            return ("layout \(layout)", { $0.candidateLayout = layout })
        case 3: return ("live conversion", { $0.liveConversion.toggle() })
        case 4: return ("predictions", { $0.japanesePredictions.toggle() })
        case 5: return ("typo correction", { $0.typoCorrection.toggle() })
        case 6: return ("kana input", { $0.kanaInput.toggle() })
        case 7: return ("fuzzy pinyin", { $0.fuzzyPinyin = $0.fuzzyPinyin.isEmpty ? Set(FuzzyPinyin.allCases) : [] })
        case 8:
            let scheme = pick(PinyinScheme.self)
            return ("scheme \(scheme)", { $0.pinyinScheme = scheme })
        case 9:
            let keyboard = pick(ChineseKeyboard.self)
            return ("keyboard \(keyboard)", { $0.chineseKeyboard = keyboard })
        case 10:
            let width = pick(PunctuationWidth.self)
            return ("punctuation \(width)", { $0.punctuationWidth = width })
        default:
            let modes: [[InputMode]] = [[.chinese, .japanese, .english], [.japanese, .chinese, .english], [.chinese, .english], [.japanese, .english]]
            let enabled = modes[random.next(below: modes.count)]
            return ("modes \(enabled.map { "\($0)" }.joined(separator: ","))", { $0.enabledModes = enabled })
        }
    }

    /// A change to the learned words from outside the composition.
    private static func randomWordsChange(_ random: inout SplitMix, mode: InputMode) -> (String, (LearnedStore) -> Void) {
        let words = mode == .chinese ? [("ceshi", "测试"), ("nihao", "你好"), ("zhongwen", "中文")] : [("てすと", "テスト"), ("すぐ", "直ぐ"), ("にほん", "日本")]
        switch random.next(below: 4) {
        case 0:
            let (reading, text) = words[random.next(below: words.count)]
            return ("add \(text)", { _ = $0.addUserWord(reading: reading, text: text, mode: mode) })
        case 1:
            let count = 1 + random.next(below: 3)
            return ("delete \(count)", { store in store.delete(ids: store.allWords(mode: mode).prefix(count).map(\.id)) })
        case 2: return ("forget", { $0.forget() })
        default: return ("delete all", { $0.deleteAll(mode: mode) })
        }
    }

    /// A key a person might press while composing.
    private static func randomKey(_ random: inout SplitMix, mode: InputMode, zhuyin: ZhuyinLayout?) -> (String, KeyInput) {
        func special(_ name: String, _ keyCode: UInt16, _ modifiers: KeyModifiers = []) -> (String, KeyInput) {
            (name, KeyInput(keyCode: keyCode, characters: "", modifiers: modifiers))
        }
        func printable(_ character: Character, shift: Bool = false, typing shifted: Character? = nil) -> (String, KeyInput) {
            let typed = shifted ?? (shift ? Character(character.uppercased()) : character)
            return (String(typed), KeyInput(keyCode: keyCodes[character] ?? 0, characters: String(typed), charactersIgnoringModifiers: String(character), modifiers: shift ? .shift : []))
        }
        switch random.next(below: 112) {
        case 0..<55 where zhuyin != nil && mode == .chinese:
            // Symbols three times as often as tones, as syllables have them.
            let layout = zhuyinKeys(zhuyin ?? .standard)
            let keys = random.next(below: 4) == 0 ? layout.tones : layout.symbols
            return printable(keys[random.next(below: keys.count)])
        case 0..<55:
            let syllables = mode == .japanese ? japaneseSyllables : pinyinSyllables
            let syllable = String(syllables[random.next(below: syllables.count)])
            // One key of it; the rest follow as the next keys would.
            return printable(syllable[syllable.index(syllable.startIndex, offsetBy: random.next(below: syllable.count))])
        case 55..<60:
            return printable(Character(UnicodeScalar(UInt8(97 + random.next(below: 26)))), shift: random.next(below: 4) == 0)
        case 60..<68: return ("␣", KeyInput(keyCode: VirtualKey.space, characters: " "))
        case 68..<73: return ("⌫", KeyInput(keyCode: VirtualKey.delete, characters: "\u{7f}"))
        case 73..<74: return ("⇧⌫", KeyInput(keyCode: VirtualKey.delete, characters: "\u{7f}", modifiers: .shift))
        case 74..<78: return printable(Character(String(1 + random.next(below: 9))))
        case 78..<81: return special("←", VirtualKey.left)
        case 81..<84: return special("→", VirtualKey.right)
        case 84..<86: return special("⇧←", VirtualKey.left, .shift)
        case 86..<88: return special("⇧→", VirtualKey.right, .shift)
        case 88..<90: return special("↓", VirtualKey.down)
        case 90..<91: return special("↑", VirtualKey.up)
        case 91..<92: return special("⇟", VirtualKey.pageDown)
        case 92..<93: return special("⇥", VirtualKey.tab)
        case 93..<96: return ("⎋", KeyInput(keyCode: VirtualKey.escape, characters: "\u{1b}"))
        case 96..<98: return ("⏎", KeyInput(keyCode: VirtualKey.returnKey, characters: "\r"))
        case 100..<102:
            let keys: [(String, UInt16)] = [("F6", VirtualKey.f6), ("F7", VirtualKey.f7), ("F8", VirtualKey.f8), ("F9", VirtualKey.f9), ("F10", VirtualKey.f10)]
            let (name, code) = keys[random.next(below: keys.count)]
            return special(name, code)
        case 102..<104: return special("⌃⌫", VirtualKey.delete, .control)
        case 104: return special("英数", VirtualKey.eisu)
        case 105: return special("かな", VirtualKey.kana)
        case 106:
            let letter = Character(UnicodeScalar(UInt8(97 + random.next(below: 26))))
            return ("⌥\(letter)", KeyInput(keyCode: keyCodes[letter] ?? 0, characters: String(letter), charactersIgnoringModifiers: String(letter), modifiers: .option))
        case 107:
            // ⌃⇧K and ⌃⇧J choose katakana and hiragana; ⌃⇧R reconverts.
            let letter = Array("kjr")[random.next(below: 3)]
            return ("⌃⇧\(letter.uppercased())", KeyInput(keyCode: keyCodes[letter] ?? 0, characters: "", charactersIgnoringModifiers: String(letter), modifiers: [.control, .shift]))
        case 108..<110:
            // The Emacs keys, and a few that are no binding.
            let letter = Array("hdaebfngmiojkl;[xc")[random.next(below: 18)]
            return ("⌃\(letter)", KeyInput(keyCode: keyCodes[letter] ?? 0, characters: "", charactersIgnoringModifiers: String(letter), modifiers: .control))
        case 110:
            let keys: [(String, UInt16)] = [("⇞", VirtualKey.pageUp), ("↖", VirtualKey.home), ("↘", VirtualKey.end), ("⌦", VirtualKey.forwardDelete)]
            let (name, code) = keys[random.next(below: keys.count)]
            return special(name, code)
        case 111: return ("⇧␣", KeyInput(keyCode: VirtualKey.space, characters: " ", modifiers: .shift))
        case 98..<100:
            let punctuation = Array(",.?!-[]<>")[random.next(below: 9)]
            switch punctuation {
            case "?": return printable("/", shift: true, typing: "?")
            case "!": return printable("1", shift: true, typing: "!")
            case "<": return printable(",", shift: true, typing: "<")
            case ">": return printable(".", shift: true, typing: ">")
            default: return printable(punctuation)
            }
        default: return ("⏎", KeyInput(keyCode: VirtualKey.returnKey, characters: "\r"))
        }
    }

    /// macOS virtual key codes of the ANSI layout, which kana input reads.
    private static let keyCodes: [Character: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
        "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
        "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F,
        "u": 0x20, "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29, ",": 0x2B,
        "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F,
    ]
}

/// A field that keeps what was committed, which is also the text before
/// the caret, and the marked text. A selection is the end of what was
/// committed, and what is typed or marked next replaces it.
@MainActor
private final class FuzzField: InputClient {
    private(set) var committed = ""
    private(set) var marked: [CompositionSegment] = []
    private var selection = 0
    let bundleIdentifier: String?

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    func reset() {
        committed = ""
        marked = []
        selection = 0
    }

    func select(last count: Int) {
        guard marked.isEmpty else { return }
        selection = min(count, committed.count)
    }

    func click() { selection = 0 }

    private func replaceSelection() {
        committed.removeLast(selection)
        selection = 0
    }

    func commit(_ text: String) {
        replaceSelection()
        committed += text
        marked = []
    }

    /// What the app does with a key Sugu passes on.
    func typeUnhandled(_ key: KeyInput) {
        if key.keyCode == VirtualKey.delete, selection > 0 {
            replaceSelection()
        } else if key.keyCode == VirtualKey.delete, !committed.isEmpty {
            committed.removeLast()
        } else if !key.isShortcut, let character = key.printable {
            replaceSelection()
            committed.append(character)
        } else {
            // Any other key collapses the selection where it ends.
            selection = 0
        }
    }

    func setMarkedText(_ segments: [CompositionSegment], caret: Int) {
        if !segments.isEmpty { replaceSelection() }
        marked = segments
    }

    func textBeforeCaret(limit: Int) -> String? { String(committed.dropLast(selection).suffix(limit)) }
    func textAfterCaret(limit: Int) -> String? { "" }

    func deleteBeforeCaret(count: Int) -> Bool {
        guard committed.count - selection >= count else { return false }
        let selected = committed.suffix(selection)
        committed = String(committed.dropLast(selection).dropLast(count)) + selected
        return true
    }

    func selectedText() -> String? { selection > 0 ? String(committed.suffix(selection)) : nil }
}

/// A small deterministic generator (SplitMix64), so a seed replays.
struct SplitMix {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(below bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }
}
