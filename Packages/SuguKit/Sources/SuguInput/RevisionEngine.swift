import SuguCore

/// Selected text being translated or rewritten. The text stays as it was,
/// as the first candidate, until a result is chosen; results from the
/// model follow it when they arrive (ADR 0004, decision 4).
@MainActor
final class RevisionEngine: CompositionEngine {
    let original: String
    let task: TextTask
    let traits = EngineTraits(composition: .live, learnsCommits: false, takesSuguCandidates: false, revisesText: true)
    private(set) var state = CompositionState.empty
    private var results: [String] = []

    init(original: String, task: TextTask) {
        self.original = original
        self.task = task
        refresh()
    }

    func show(_ results: [String]) {
        self.results = results.filter { $0 != original }
        refresh()
    }

    func accepts(_ character: Character) -> Bool { false }
    func insert(_ input: String) {}
    func deleteBackward() {}
    func deleteForward() {}
    func moveCaret(_ motion: CaretMotion) {}
    func convert() -> Bool { false }
    func cancelConversion() {}
    func highlight(_ index: Int) {}
    func moveFocus(forward: Bool) {}
    func resizeFocus(by delta: Int) {}

    func select(_ index: Int) -> SelectionResult {
        let texts = [original] + results
        guard texts.indices.contains(index) else { return .continued }
        let commit = Commit(text: texts[index], reading: original)
        clear()
        return .committed(commit)
    }

    func commitConverted() -> Commit? { commitRaw() }

    func commitRaw() -> Commit? {
        guard !state.isEmpty else { return nil }
        clear()
        return Commit(text: original, reading: original)
    }

    func clear() {
        results = []
        state = .empty
    }

    func restore(reading: String) {}
    func setLeftContext(_ text: String) {}

    private func refresh() {
        state = CompositionState(
            segments: [CompositionSegment(original, role: .input)],
            caret: original.count,
            candidates: ([original] + results).enumerated().map { Candidate(text: $1, source: .engine(index: $0)) },
            highlightedIndex: nil,
            phase: .composing,
            reading: original
        )
    }
}
