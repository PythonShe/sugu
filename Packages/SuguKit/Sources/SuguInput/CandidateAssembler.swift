import SuguCore
import SuguLearning

/// Builds the list the user sees from the engine's candidates plus Sugu's
/// own: learned and user words, computed candidates, and the typed letters
/// as Latin text. Also applies left-context ranking.
@MainActor
struct CandidateAssembler {
    var computed: ComputedCandidates
    var latin: LatinInference?
    var store: LearnedStore?

    struct Input {
        var mode: InputMode
        var state: CompositionState
        /// Text left of the caret (and, when enabled, elsewhere in the
        /// field) whose words should rank first.
        var context: String
        /// Rows per page, so the Latin candidate stays on the first page.
        var pageSize: Int
    }

    func assemble(_ input: Input) -> [Candidate] {
        let state = input.state
        var engine = state.candidates
        if !input.context.isEmpty {
            engine = rerank(engine, context: input.context)
        }
        // Sugu's candidates replace the whole reading, so they only apply
        // while nothing in the composition has been converted yet.
        let wholeReading = !state.segments.contains { $0.role == .converted } && !state.reading.isEmpty
        guard wholeReading else { return engine }

        let learned = (store?.lookup(state.reading, mode: input.mode) ?? []).map {
            Candidate(text: $0.text, source: .learned)
        }
        let computedCandidates = computed.candidates(for: state.reading, mode: input.mode)
        var latinFirst: Candidate?
        var latinLast: Candidate?
        if input.mode == .chinese, let latin, state.phase == .composing {
            let typed = state.reading
            let candidate = Candidate(text: typed, source: .latin)
            switch latin.placement(for: typed) {
            case .first: latinFirst = candidate
            case .last: latinLast = candidate
            }
        } else if input.mode == .japanese, let latin, state.phase == .composing, latin.isEnglishWord(state.typedText) {
            latinLast = Candidate(text: state.typedText, source: .latin)
        }

        var seen = Set<String>()
        var result: [Candidate] = []
        func append(_ candidate: Candidate) {
            if seen.insert(candidate.text).inserted { result.append(candidate) }
        }
        latinFirst.map(append)
        learned.forEach(append)
        if let first = engine.first { append(first) }
        computedCandidates.forEach(append)
        engine.dropFirst().forEach(append)
        if let latinLast {
            if seen.insert(latinLast.text).inserted {
                result.insert(latinLast, at: min(result.count, max(1, input.pageSize - 1)))
            }
        }
        return result
    }

    /// Moves candidates that already appear in the context ahead of the
    /// engine's first choice when they plausibly cover the same input (same
    /// length as the first candidate, two or more characters).
    func rerank(_ candidates: [Candidate], context: String) -> [Candidate] {
        guard let first = candidates.first, first.text.count >= 2 else { return candidates }
        let window = candidates.prefix(10)
        let hits = window.filter { $0.text.count == first.text.count && $0.text != first.text && context.contains($0.text) }
        guard !hits.isEmpty, !context.contains(first.text) else { return candidates }
        let hitTexts = Set(hits.map(\.text))
        return hits + candidates.filter { !hitTexts.contains($0.text) }
    }
}
