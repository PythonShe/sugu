import SuguCore

/// Holds the letters of a Chinese composition typed while librime is still
/// being set up, so they are not typed into the document; the session hands
/// them to librime once it is ready. Should setup fail, the letters can
/// still be committed as typed.
@MainActor
final class LoadingEngine: CompositionEngine {
    private var text = ""
    private var caret = 0
    let traits = EngineTraits(composition: .live, learnsCommits: false, takesSuguCandidates: false)
    private(set) var state = CompositionState.empty
    /// Holds Zhuyin keys, tones and Space among them, rather than letters.
    var holdsZhuyin = false

    func accepts(_ character: Character) -> Bool {
        if holdsZhuyin { return Zhuyin.keyboard[character] != nil || (Zhuyin.toneKeys[character] != nil && !text.isEmpty) }
        return character.isASCIILowercaseLetter || (character == "'" && !text.isEmpty)
    }

    func insert(_ input: String) {
        text.insert(contentsOf: input, at: text.index(text.startIndex, offsetBy: caret))
        caret += input.count
        refresh()
    }

    func deleteBackward() {
        guard caret > 0 else { return }
        text.remove(at: text.index(text.startIndex, offsetBy: caret - 1))
        caret -= 1
        refresh()
    }

    func deleteForward() {
        guard caret < text.count else { return }
        text.remove(at: text.index(text.startIndex, offsetBy: caret))
        refresh()
    }

    func moveCaret(_ motion: CaretMotion) {
        // Zhuyin keys replay in order; the engine's caret is by syllable.
        guard !holdsZhuyin else { return }
        switch motion {
        case .left: caret = max(0, caret - 1)
        case .right: caret = min(text.count, caret + 1)
        case .start: caret = 0
        case .end: caret = text.count
        }
        refresh()
    }

    func convert() -> Bool { false }
    func cancelConversion() {}
    func highlight(_ index: Int) {}
    func select(_ index: Int) -> SelectionResult { .continued }
    func moveFocus(forward: Bool) {}
    func resizeFocus(by delta: Int) {}
    func commitConverted() -> Commit? { commitRaw() }

    func commitRaw() -> Commit? {
        guard !text.isEmpty else { return nil }
        let commit = Commit(text: text, reading: text)
        clear()
        return commit
    }

    func clear() {
        text = ""
        caret = 0
        state = .empty
    }

    func restore(reading: String) {
        text = reading
        caret = reading.count
        refresh()
    }

    func setLeftContext(_ text: String) {}

    private func refresh() {
        guard !text.isEmpty else { state = .empty; return }
        state = CompositionState(
            segments: [CompositionSegment(text, role: .input)],
            caret: caret,
            candidates: [],
            highlightedIndex: nil,
            phase: .composing,
            reading: text
        )
    }
}
