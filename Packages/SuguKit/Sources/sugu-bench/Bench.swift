import Darwin
import Foundation
import SuguCore
import SuguEngines
import SuguInput
import SuguLearning
import SuguRime

/// Drives `InputSession` with real engines the way the shell does: one key
/// event at a time into a field, timing each keystroke from event to
/// updated candidates.
@MainActor
enum Bench {
    struct Case {
        var typed: String
        var expected: String
        /// Text before the caret while it is typed.
        var context = ""
    }

    static func run(data: URL, bench: URL, zenzaiModel: URL? = nil, grammarModel: URL? = nil, languageModels: Bool = true, configure: (inout Preferences) -> Void = { _ in }) async throws -> Report {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-bench-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        var preferences = Preferences()
        preferences.learningEnabled = false
        preferences.rememberModePerApp = false
        configure(&preferences)
        let locations = EngineHub.Locations(
            rimeShared: data.appendingPathComponent("Rime"),
            rimeUser: work.appendingPathComponent("Rime"),
            azooKey: work.appendingPathComponent("AzooKey"),
            models: work.appendingPathComponent("Models"),
            lexicon: data.appendingPathComponent("Lexicon"),
            languageModels: languageModels ? data.appendingPathComponent("LM") : nil
        )
        if let zenzaiModel {
            try FileManager.default.createDirectory(at: locations.models, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: locations.zenzaiModel, withDestinationURL: zenzaiModel)
            preferences.zenzaiEnabled = true
        }
        if let grammarModel {
            try FileManager.default.createDirectory(at: locations.rimeUser, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: locations.grammarModel(named: RimeSchema.grammarLanguage), withDestinationURL: grammarModel)
            preferences.useGrammarModel = true
        }
        // Learning off for the accuracy sets; the learned-words set teaches
        // words through the store directly.
        let lexicon = data.appendingPathComponent("Lexicon")
        let syllables = Lexicon.load(Lexicon.syllablesFile, in: lexicon)
        let store = try LearnedStore(url: work.appendingPathComponent("learned.sqlite"), syllabary: PinyinSyllabary(syllables))
        let engines = EngineHub(
            locations: locations,
            preferences: preferences,
            store: store,
            version: "bench",
            chineseWordsDelay: .zero
        )
        await engines.waitUntilReady()
        engines.prepare(.japanese)
        await engines.waitForJapaneseDictionary()
        await engines.waitForZenzai()
        let latin = LatinInference(
            syllables: syllables,
            englishWords: Lexicon.load(Lexicon.englishWordsFile, in: lexicon)
        )
        let session = InputSession(preferences: preferences, engines: engines, store: store, latin: latin)
        let field = Field()
        session.attach(field)

        var report = Report()
        let zhuyin = preferences.chineseKeyboard == .zhuyin
        if zhuyin {
            // The Chinese set typed in Zhuyin, each character with the tone
            // librime ranks it highest under, as reconversion finds it.
            let cases = try load(bench.appendingPathComponent("zh.tsv")).compactMap { test -> Case? in
                guard let codes = engines.chineseReading(of: test.expected), let syllables = Zhuyin.syllables(ofCodes: codes) else { return nil }
                return Case(typed: syllables.map { Zhuyin.keys(typing: $0, on: preferences.zhuyinLayout) }.joined(), expected: test.expected)
            }
            report.chinese = measure(session, mode: .chinese, cases: cases, zhuyin: true)
        } else {
            report.chinese = measure(session, mode: .chinese, cases: try load(bench.appendingPathComponent("zh.tsv")))
        }
        report.japanese = measure(session, mode: .japanese, cases: try load(bench.appendingPathComponent("ja.tsv")))
        if preferences.phoneticRomaji {
            report.phonetic = measure(session, mode: .japanese, cases: try load(bench.appendingPathComponent("ja-phonetic.tsv")))
        }
        if preferences.contextualN {
            report.contextualN = measure(session, mode: .japanese, cases: try load(bench.appendingPathComponent("ja-n.tsv")))
        }
        report.memory = Memory.current()

        // The same readings after different text: with the field read and
        // with it hidden.
        for (mode, name) in [(InputMode.chinese, "zh"), (.japanese, "ja")] where mode != .chinese || !zhuyin {
            let set = bench.appendingPathComponent("\(name)-context.tsv")
            guard FileManager.default.fileExists(atPath: set.path) else { continue }
            let cases = try load(set)
            var result = ContextResult(without: measure(session, mode: mode, cases: cases.map { Case(typed: $0.typed, expected: $0.expected) }))
            result.with = measure(session, mode: mode, cases: cases, field: field)
            report.context[name] = result
        }

        // Words the user taught, in sentences: before teaching them, after,
        // and the main set again after, per language.
        for (mode, name) in [(InputMode.chinese, "zh"), (.japanese, "ja")] where mode != .chinese || !zhuyin {
            let set = bench.appendingPathComponent("\(name)-learned.tsv")
            guard FileManager.default.fileExists(atPath: set.path) else { continue }
            let (words, cases) = try loadLearned(set)
            var result = LearnedResult(before: measure(session, mode: mode, cases: cases))
            for (reading, text) in words {
                store.learn(Commit(text: text, reading: reading), mode: mode)
            }
            engines.learnedWordsDidChange()
            await engines.waitForLearnedWords()
            result.after = measure(session, mode: mode, cases: cases)
            result.mainSet = measure(session, mode: mode, cases: try load(bench.appendingPathComponent("\(name).tsv")))
            report.learned[name] = result
        }

        // Sentences the user typed earlier, learned as n-grams only, then
        // readings after new text that share their habits (D-079): before,
        // after, and the main and context sets again after.
        for (mode, name) in [(InputMode.chinese, "zh"), (.japanese, "ja")] where mode != .chinese || !zhuyin {
            let set = bench.appendingPathComponent("\(name)-phrases.tsv")
            guard FileManager.default.fileExists(atPath: set.path) else { continue }
            let (sentences, cases) = try loadPhrases(set)
            var result = PhraseResult(before: measure(session, mode: mode, cases: cases, field: field))
            for sentence in sentences {
                var commit = Commit(text: sentence, reading: sentence, mayBeWord: false)
                commit.context = ""
                store.learn(commit, mode: mode)
            }
            result.after = measure(session, mode: mode, cases: cases, field: field)
            result.mainSet = measure(session, mode: mode, cases: try load(bench.appendingPathComponent("\(name).tsv")))
            let context = bench.appendingPathComponent("\(name)-context.tsv")
            if FileManager.default.fileExists(atPath: context.path) {
                result.contextSet = measure(session, mode: mode, cases: try load(context), field: field)
            }
            report.phrases[name] = result
        }
        return report
    }

    /// Sentences to learn (rows starting with +) and the cases sharing them.
    static func loadPhrases(_ url: URL) throws -> (sentences: [String], cases: [Case]) {
        let lines = try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("#") }
        let sentences = lines.filter { $0.hasPrefix("+") }.map { String($0.dropFirst()) }
        let cases = lines.filter { !$0.hasPrefix("+") }.compactMap { line -> Case? in
            let fields = line.split(separator: "\t").map(String.init)
            return fields.count == 3 ? Case(typed: fields[1], expected: fields[2], context: fields[0]) : nil
        }
        return (sentences, cases)
    }

    /// Words to teach (rows starting with +) and the sentences using them.
    static func loadLearned(_ url: URL) throws -> (words: [(String, String)], cases: [Case]) {
        var words: [(String, String)] = []
        var cases: [Case] = []
        for line in try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            guard fields.count == 2 else { continue }
            if fields[0].hasPrefix("+") {
                words.append((String(fields[0].dropFirst()), String(fields[1])))
            } else {
                cases.append(Case(typed: String(fields[0]), expected: String(fields[1])))
            }
        }
        return (words, cases)
    }

    /// Rows of typed and expected text, after the context when there are
    /// three columns.
    static func load(_ url: URL) throws -> [Case] {
        try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.split(separator: "\t").map(String.init)
            switch fields.count {
            case 2: return Case(typed: fields[0], expected: fields[1])
            case 3: return Case(typed: fields[1], expected: fields[2], context: fields[0])
            default: return nil
            }
        }
    }

    /// Keys a person types for a test reading: no spaces (Space converts),
    /// ü as v; Zhuyin keys as they are, Space the first tone.
    static func keys(for typed: String, zhuyin: Bool = false) -> [Character] {
        guard !zhuyin else { return Array(typed) }
        return typed.replacingOccurrences(of: "ü", with: "v").filter { $0 != " " }.map { $0 }
    }

    /// With `field`, each case is typed after its context. Zhuyin's
    /// sentence is what the field shows once the keys are typed.
    private static func measure(_ session: InputSession, mode: InputMode, cases: [Case], field: Field? = nil, zhuyin: Bool = false) -> LanguageResult {
        session.setMode(mode)
        // Load the engine before timing.
        _ = session.handle(key(zhuyin ? "1" : "a"))
        _ = session.handle(KeyInput(keyCode: VirtualKey.escape, characters: "\u{1b}"))

        var result = LanguageResult()
        defer { field?.context = "" }
        for test in cases {
            field?.context = test.context
            for character in keys(for: test.typed, zhuyin: zhuyin) {
                let started = DispatchTime.now().uptimeNanoseconds
                _ = session.handle(key(character))
                result.keystrokes.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
            }
            let output: String
            switch mode {
            case .chinese where zhuyin:
                output = session.display.segments.map(\.text).joined()
            case .japanese:
                let started = DispatchTime.now().uptimeNanoseconds
                _ = session.handle(KeyInput(keyCode: VirtualKey.space, characters: " "))
                result.conversions.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
                output = session.display.segments.map(\.text).joined()
            default:
                output = session.display.candidates?.candidates.first?.text ?? ""
            }
            let inPage = session.display.candidates?.candidates.contains { $0.text == test.expected } ?? false
            result.record(expected: test.expected, output: output, inPage: inPage || output == test.expected,
                          keys: keys(for: test.typed, zhuyin: zhuyin).count + 1)
            _ = session.handle(KeyInput(keyCode: VirtualKey.escape, characters: "\u{1b}"))
            _ = session.handle(KeyInput(keyCode: VirtualKey.escape, characters: "\u{1b}"))
        }
        return result
    }

    private static func key(_ character: Character) -> KeyInput {
        let keyCode: UInt16 = character == "," ? 0x2B : character == " " ? VirtualKey.space : 0
        return KeyInput(keyCode: keyCode, characters: String(character))
    }
}

/// A text field that accepts everything and exposes only `context`, the
/// text before the caret, which typing leaves as it is.
@MainActor
private final class Field: InputClient {
    var context = ""
    var bundleIdentifier: String? { "com.zheng-she.sugu-bench" }
    func commit(_ text: String) {}
    func setMarkedText(_ segments: [CompositionSegment], caret: Int) {}
    func textBeforeCaret(limit: Int) -> String? { context.isEmpty ? nil : String(context.suffix(limit)) }
    func textAfterCaret(limit: Int) -> String? { nil }
    func deleteBeforeCaret(count: Int) -> Bool { false }
    func selectedText() -> String? { nil }
}
