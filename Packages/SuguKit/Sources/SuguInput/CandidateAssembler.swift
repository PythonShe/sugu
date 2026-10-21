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
        /// Whether the engine takes Sugu's candidates (not an expression).
        var includesSuguCandidates = true
        var state: CompositionState
        /// Text left of the caret whose words should rank first.
        var context: String
        /// Text elsewhere in the field whose words should also rank first.
        var vocabulary = ""
        /// Rows per page, so the Latin candidate stays on the first page.
        var pageSize: Int
        /// The script Chinese is typed in, which learned words are shown in.
        var chineseScript: ChineseScript = .simplified
        /// Chinese text in the script in use (see `EngineSource`).
        var chineseText: (String) -> String? = { _ in nil }
        /// Whether Japanese names also offer their Chinese form.
        var offersChineseForms = false
    }

    func assemble(_ input: Input) -> [Candidate] {
        let state = input.state
        guard input.includesSuguCandidates else { return state.candidates }
        var engine = state.candidates
        if !input.context.isEmpty || !input.vocabulary.isEmpty {
            engine = rerank(engine, context: input.context, vocabulary: input.vocabulary)
        }
        // Sugu's candidates replace the whole reading, so they only apply
        // while nothing in the composition has been converted yet.
        let wholeReading = !state.segments.contains { $0.role == .converted } && !state.reading.isEmpty
        guard wholeReading else { return engine }

        // In the script in use, as librime gives its own candidates.
        let learned = (store?.lookup(state.reading, mode: input.mode) ?? []).map { word in
            (candidate: Candidate(text: store?.text(of: word, in: input.chineseScript) ?? word.shown, source: .learned), isEstablished: word.isEstablished)
        }
        var computedCandidates = computed.candidates(for: state.reading, mode: input.mode)
        if input.mode == .chinese {
            computedCandidates = computedCandidates.map { candidate in
                var candidate = candidate
                candidate.text = input.chineseText(candidate.text) ?? candidate.text
                return candidate
            }
        }
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
        // Established words lead; a word chosen once follows the engine's
        // first choice (`LearnedWord.isEstablished`).
        learned.filter(\.isEstablished).forEach { append($0.candidate) }
        if let first = engine.first { append(first) }
        learned.filter { !$0.isEstablished }.forEach { append($0.candidate) }
        computedCandidates.forEach(append)
        // Symbols by name come after the words of the same reading the
        // engine likes best (やじるし: 矢印, then →).
        let symbols = input.mode == .japanese ? JapaneseSymbolNames.symbols(for: state.reading).map { Candidate(text: $0, source: .computed) } : []
        engine.dropFirst().prefix(1).forEach(append)
        symbols.forEach(append)
        engine.dropFirst(2).forEach(append)
        if let latinLast {
            if seen.insert(latinLast.text).inserted {
                result.insert(latinLast, at: min(result.count, max(1, input.pageSize - 1)))
            }
        }
        if input.mode == .japanese, input.offersChineseForms {
            result = withChineseForms(result, pageSize: input.pageSize, chineseText: input.chineseText, seen: &seen)
        }
        return result
    }

    /// Puts the Chinese form of each name on the first page right after it
    /// (東京 → 东京), for writing about Japan in Chinese.
    private func withChineseForms(_ candidates: [Candidate], pageSize: Int, chineseText: (String) -> String?, seen: inout Set<String>) -> [Candidate] {
        var result: [Candidate] = []
        for (index, candidate) in candidates.enumerated() {
            result.append(candidate)
            guard index < pageSize, candidate.isProperNoun, let form = chineseText(candidate.text),
                  form != candidate.text, seen.insert(form).inserted else { continue }
            result.append(Candidate(text: form, annotation: candidate.annotation, source: .chineseForm))
        }
        return result
    }

    /// Moves candidates that already appear in the context or vocabulary
    /// ahead of the engine's first choice when they plausibly cover the same
    /// input (same length as the first candidate, two or more characters).
    func rerank(_ candidates: [Candidate], context: String, vocabulary: String = "") -> [Candidate] {
        guard let first = candidates.first, first.text.count >= 2 else { return candidates }
        func appears(_ text: String) -> Bool { context.contains(text) || vocabulary.contains(text) }
        let window = candidates.prefix(10)
        let hits = window.filter { $0.text.count == first.text.count && $0.text != first.text && appears($0.text) }
        guard !hits.isEmpty, !appears(first.text) else { return candidates }
        let hitTexts = Set(hits.map(\.text))
        return hits + candidates.filter { !hitTexts.contains($0.text) }
    }
}
