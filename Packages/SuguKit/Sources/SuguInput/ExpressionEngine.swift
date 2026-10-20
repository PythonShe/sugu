import SuguCore

/// Composes a number or expression after Chinese mode's `v` prefix and
/// offers computed candidates for it (`v1234` → 一千二百三十四).
@MainActor
final class ExpressionEngine: CompositionEngine {
    private let computed: ComputedCandidates
    private var text = ""
    private var caret = 0
    private(set) var state = CompositionState.empty

    init(computed: ComputedCandidates) {
        self.computed = computed
    }

    func accepts(_ character: Character) -> Bool {
        if text.isEmpty { return character == ComputedCandidates.chineseNumberPrefix }
        return character.isASCIIDigitCharacter || "+-*/^%().".contains(character)
    }

    func insert(_ input: String) {
        let index = text.index(text.startIndex, offsetBy: caret)
        text.insert(contentsOf: input, at: index)
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
        switch motion {
        case .left: caret = max(0, caret - 1)
        case .right: caret = min(text.count, caret + 1)
        case .start: caret = 0
        case .end: caret = text.count
        }
        refresh()
    }

    func convert() -> Bool { !text.isEmpty }
    func cancelConversion() {}
    func highlight(_ index: Int) {
        guard state.candidates.indices.contains(index) else { return }
        state.highlightedIndex = index
    }
    func moveFocus(forward: Bool) {}
    func resizeFocus(by delta: Int) {}

    func select(_ index: Int) -> SelectionResult {
        guard let candidate = state.candidates[safe: index] else { return .continued }
        let commit = Commit(text: candidate.text, reading: text)
        clear()
        return .committed(commit)
    }

    func commitConverted() -> Commit? {
        guard !text.isEmpty else { return nil }
        if let index = state.highlightedIndex, state.candidates.indices.contains(index) {
            if case .committed(let commit) = select(index) { return commit }
        }
        return commitRaw()
    }

    func commitRaw() -> Commit? {
        guard !text.isEmpty else { return nil }
        let raw = String(text.dropFirst())
        let commit = Commit(text: raw.isEmpty ? text : raw, reading: text)
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
        let candidates = computed.candidates(for: text, mode: .chinese).enumerated().map {
            Candidate(text: $1.text, source: .engine(index: $0))
        }
        state = CompositionState(
            segments: [CompositionSegment(text, role: .input)],
            caret: caret,
            candidates: candidates,
            highlightedIndex: candidates.isEmpty ? nil : 0,
            phase: .composing,
            reading: text
        )
    }
}
