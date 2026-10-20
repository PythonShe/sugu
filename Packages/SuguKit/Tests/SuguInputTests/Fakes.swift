import Foundation
import SuguCore
@testable import SuguInput

/// A text field that records what the session does to it.
@MainActor
final class FakeClient: InputClient {
    var bundleIdentifier: String?
    var document = ""
    var marked: [CompositionSegment] = []
    var exposesText = true
    /// Text right of the caret, which commits do not touch.
    var documentAfterCaret = ""

    init(bundleIdentifier: String? = "com.example.editor") {
        self.bundleIdentifier = bundleIdentifier
    }

    var markedText: String { marked.map(\.text).joined() }

    func commit(_ text: String) {
        document += text
        marked = []
    }

    func setMarkedText(_ segments: [CompositionSegment], caret: Int) {
        marked = segments
    }

    func textBeforeCaret(limit: Int) -> String? {
        exposesText ? String(document.suffix(limit)) : nil
    }

    func textAfterCaret(limit: Int) -> String? {
        exposesText ? String(documentAfterCaret.prefix(limit)) : nil
    }

    func deleteBeforeCaret(count: Int) -> Bool {
        guard exposesText, document.count >= count else { return false }
        document.removeLast(count)
        return true
    }

    func selectedText() -> String? { nil }
}

/// An engine with a fixed table of readings, standing in for librime or
/// AzooKey so session behavior can be tested exactly.
@MainActor
final class FakeEngine: CompositionEngine {
    var table: [String: [String]]
    var converts: Bool
    /// Candidates the engine tags as names.
    var properNouns: Set<String> = []
    /// Readings whose first candidate covers only their start, as librime
    /// selects a phrase for the first syllables and keeps composing.
    var partial: [String: (consumed: Int, text: String)] = [:]
    private var input = ""
    private var selected = ""
    private var converting = false
    private var highlighted = 0
    private(set) var state = CompositionState.empty

    init(table: [String: [String]], converts: Bool = false) {
        self.table = table
        self.converts = converts
    }

    func accepts(_ character: Character) -> Bool { character.isASCIILowercaseLetter || character == "'" }
    func insert(_ text: String) { input += text; converting = false; refresh() }
    func deleteBackward() { if !input.isEmpty { input.removeLast() }; refresh() }
    func deleteForward() {}
    func moveCaret(_ motion: CaretMotion) {}
    func convert() -> Bool {
        guard converts, !input.isEmpty else { return false }
        if converting { highlighted += 1 } else { converting = true; highlighted = 0 }
        refresh()
        return true
    }
    func cancelConversion() { converting = false; refresh() }
    func highlight(_ index: Int) { highlighted = index; refresh() }
    func select(_ index: Int) -> SelectionResult {
        if index == 0, let split = partial[input] {
            selected += split.text
            input.removeFirst(split.consumed)
            refresh()
            return .continued
        }
        let words = table[input] ?? []
        guard words.indices.contains(index) else { return .continued }
        let commit = Commit(text: selected + words[index], reading: input, clauses: [.init(reading: input, text: words[index])])
        clear()
        return .committed(commit)
    }
    func moveFocus(forward: Bool) {}
    func resizeFocus(by delta: Int) {}
    func commitConverted() -> Commit? {
        guard !input.isEmpty else { return nil }
        if converting, case .committed(let commit) = select(highlighted) { return commit }
        // Like librime, an engine without a conversion step commits its
        // first candidate.
        if !converts, table[input]?.isEmpty == false, case .committed(let commit) = select(0) { return commit }
        return commitRaw()
    }
    func commitRaw() -> Commit? {
        guard !input.isEmpty else { return nil }
        let commit = Commit(text: selected + input, reading: input)
        clear()
        return commit
    }
    func clear() { input = ""; selected = ""; converting = false; highlighted = 0; state = .empty }
    func restore(reading: String) { input = reading; converting = converts; refresh() }
    private(set) var leftContext = ""
    func setLeftContext(_ text: String) { leftContext = text }

    private func refresh() {
        guard !input.isEmpty else { state = .empty; return }
        let words = table[input] ?? []
        let shown = converting ? (words[safe: highlighted] ?? input) : input
        state = CompositionState(
            segments: [CompositionSegment(shown, role: converting ? .focused : .input)],
            caret: shown.count,
            candidates: words.enumerated().map { Candidate(text: $1, source: .engine(index: $0), isProperNoun: properNouns.contains($1)) },
            highlightedIndex: converting ? highlighted : nil,
            phase: converting ? .converting : .composing,
            reading: input
        )
    }
}

@MainActor
final class FakeEngineSource: EngineSource {
    var engines: [InputMode: any CompositionEngine] = [:]
    var learnedChanges = 0
    func engine(for mode: InputMode) -> (any CompositionEngine)? { engines[mode] }
    func learnedWordsDidChange() { learnedChanges += 1 }
    var script = ChineseScript.simplified
    /// Script conversions by text, standing in for OpenCC.
    var conversions: [String: String] = [:]
    func setChineseScript(_ script: ChineseScript) { self.script = script }
    func chineseText(_ text: String) -> String? { conversions[text] }
}

@MainActor
final class MemoryModes: ModeMemory {
    var modes: [String: InputMode] = [:]
    func mode(for bundleIdentifier: String) -> InputMode? { modes[bundleIdentifier] }
    func remember(_ mode: InputMode, for bundleIdentifier: String) { modes[bundleIdentifier] = mode }
}

/// Key events as the shell would produce them.
enum Key {
    static func char(_ c: Character, _ modifiers: KeyModifiers = []) -> KeyInput {
        KeyInput(keyCode: 0, characters: String(c), modifiers: modifiers)
    }
    static let space = KeyInput(keyCode: VirtualKey.space, characters: " ")
    static let enter = KeyInput(keyCode: VirtualKey.returnKey, characters: "\r")
    static let keypadEnter = KeyInput(keyCode: VirtualKey.keypadEnter, characters: "\u{3}", modifiers: [.numericPad])
    static func keypad(_ c: Character) -> KeyInput { char(c, [.numericPad]) }
    static let escape = KeyInput(keyCode: VirtualKey.escape, characters: "\u{1B}")
    static let backspace = KeyInput(keyCode: VirtualKey.delete, characters: "\u{7F}")
    static let undo = KeyInput(keyCode: VirtualKey.delete, characters: "\u{7F}", modifiers: [.control])
    static let down = KeyInput(keyCode: VirtualKey.down, characters: "\u{F701}")
    static let f7 = KeyInput(keyCode: VirtualKey.f7, characters: "\u{F70A}")
    static let commandC = KeyInput(keyCode: 8, characters: "c", modifiers: [.command])
}
