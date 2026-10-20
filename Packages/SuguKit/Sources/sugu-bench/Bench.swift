import Darwin
import Foundation
import SuguCore
import SuguEngines
import SuguInput
import SuguLearning

/// Drives `InputSession` with real engines the way the shell does: one key
/// event at a time into a field, timing each keystroke from event to
/// updated candidates.
@MainActor
enum Bench {
    struct Case {
        var typed: String
        var expected: String
    }

    static func run(data: URL, bench: URL, zenzaiModel: URL? = nil, configure: (inout Preferences) -> Void = { _ in }) async throws -> Report {
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
            models: work.appendingPathComponent("Models")
        )
        if let zenzaiModel {
            try FileManager.default.createDirectory(at: locations.models, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: locations.zenzaiModel, withDestinationURL: zenzaiModel)
            preferences.zenzaiEnabled = true
        }
        let engines = EngineHub(
            locations: locations,
            preferences: preferences,
            store: nil,
            version: "bench"
        )
        await engines.waitUntilReady()
        let lexicon = data.appendingPathComponent("Lexicon")
        let latin = LatinInference(
            syllables: Lexicon.load(Lexicon.syllablesFile, in: lexicon),
            englishWords: Lexicon.load(Lexicon.englishWordsFile, in: lexicon)
        )
        let session = InputSession(preferences: preferences, engines: engines, store: nil, latin: latin)
        let field = Field()
        session.attach(field)

        var report = Report()
        report.chinese = measure(session, mode: .chinese, cases: try load(bench.appendingPathComponent("zh.tsv")))
        report.japanese = measure(session, mode: .japanese, cases: try load(bench.appendingPathComponent("ja.tsv")))
        report.memory = Memory.current()
        return report
    }

    static func load(_ url: URL) throws -> [Case] {
        try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline).compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.split(separator: "\t")
            guard fields.count == 2 else { return nil }
            return Case(typed: String(fields[0]), expected: String(fields[1]))
        }
    }

    /// Keys a person types for a test reading: no spaces (Space converts),
    /// ü as v.
    static func keys(for typed: String) -> [Character] {
        typed.replacingOccurrences(of: "ü", with: "v").filter { $0 != " " }.map { $0 }
    }

    private static func measure(_ session: InputSession, mode: InputMode, cases: [Case]) -> LanguageResult {
        session.setMode(mode)
        // Load the engine before timing.
        _ = session.handle(key("a"))
        _ = session.handle(KeyInput(keyCode: VirtualKey.escape, characters: "\u{1b}"))

        var result = LanguageResult()
        for test in cases {
            for character in keys(for: test.typed) {
                let started = DispatchTime.now().uptimeNanoseconds
                _ = session.handle(key(character))
                result.keystrokes.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
            }
            let output: String
            switch mode {
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
                          keys: keys(for: test.typed).count + 1)
            _ = session.handle(KeyInput(keyCode: VirtualKey.escape, characters: "\u{1b}"))
            _ = session.handle(KeyInput(keyCode: VirtualKey.escape, characters: "\u{1b}"))
        }
        return result
    }

    private static func key(_ character: Character) -> KeyInput {
        let keyCode: UInt16 = character == "," ? 0x2B : 0
        return KeyInput(keyCode: keyCode, characters: String(character))
    }
}

/// A text field that accepts everything and exposes nothing.
@MainActor
private final class Field: InputClient {
    var bundleIdentifier: String? { "io.github.pythonshe.sugu-bench" }
    func commit(_ text: String) {}
    func setMarkedText(_ segments: [CompositionSegment], caret: Int) {}
    func textBeforeCaret(limit: Int) -> String? { nil }
    func textAfterCaret(limit: Int) -> String? { nil }
    func deleteBeforeCaret(count: Int) -> Bool { false }
    func selectedText() -> String? { nil }
}
