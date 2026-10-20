import SuguCore

extension InputSession {
    // MARK: Candidate list

    var verticalLayout: Bool { preferences.candidateLayout == .vertical }
    /// Whether the active engine's first candidate is chosen by default.
    private var hasLiveCandidates: Bool { active.map { !$0.traits.hasConversionPhase } ?? false }

    func moveHighlight(by delta: Int) {
        guard let next = list.index(movingHighlightBy: delta) else { return }
        setHighlight(next)
    }

    /// Turns the candidate list by `delta` pages, as the paging keys do.
    public func turnPage(by delta: Int) {
        guard let target = list.page(turnedBy: delta) else { return }
        if list.highlight != nil || hasLiveCandidates {
            setHighlight(target * list.pageSize)
        } else {
            list.page = target
            publish()
        }
    }

    private func setHighlight(_ index: Int) {
        list.setHighlight(index)
        if let engine = active, engine.state.phase == .converting, let engineIndex = list.candidates[index].engineIndex {
            engine.highlight(engineIndex)
            // The focused clause text follows the highlight.
            list.candidates = assembled(engine.state)
        }
        publish()
    }

    /// Re-reads the engine after a change and rebuilds the list.
    func refresh() {
        guard let engine = active else { publish(); return }
        if engine.state.isEmpty {
            active = nil
            list.clear()
            publish()
            return
        }
        let state = engine.state
        list.candidates = assembled(state)
        scheduleSuggestions()
        if state.phase == .converting {
            let index = state.highlightedIndex.flatMap { engineIndex in list.candidates.firstIndex { $0.engineIndex == engineIndex } }
            list.setHighlight(index ?? 0)
        } else if !engine.traits.hasConversionPhase {
            list.setHighlight(list.isEmpty ? nil : 0)
        } else {
            list.setHighlight(nil)
        }
        publish()
    }

    private func assembled(_ state: CompositionState) -> [Candidate] {
        let candidates = assembler.assemble(.init(
            mode: mode,
            includesSuguCandidates: active?.traits.takesSuguCandidates ?? false,
            state: state,
            context: preferences.leftContextRanking ? context : "",
            vocabulary: preferences.leftContextRanking && preferences.documentVocabulary ? vocabulary : "",
            pageSize: list.pageSize,
            chineseText: { [engines] in engines.chineseText($0) },
            offersChineseForms: preferences.enabledModes.contains(.chinese)
        ))
        return mergingSuggestions(into: candidates, reading: state.reading)
    }

    func publish() {
        var segments: [CompositionSegment] = []
        var caret = 0
        var presentation: CandidatePresentation?
        if let engine = active, !engine.state.isEmpty {
            let state = engine.state
            if let transformed {
                segments = [CompositionSegment(transformed, role: .focused)]
                caret = transformed.count
            } else {
                segments = state.segments
                caret = state.caret
                // Show a highlighted prediction inline while it is chosen, and
                // Sugu's own candidates, which replace the whole reading.
                if engine.traits.hasConversionPhase, let highlighted = list.highlighted,
                   state.phase == .composing || highlighted.engineIndex == nil {
                    segments = [CompositionSegment(highlighted.text, role: .focused)]
                    caret = highlighted.text.count
                }
            }
            let showWindow: Bool
            if transformed != nil {
                showWindow = false
            } else if state.phase == .converting {
                showWindow = showsConversionWindow
            } else {
                showWindow = !engine.traits.hasConversionPhase || preferences.japanesePredictions
            }
            let page = list.currentPage
            if showWindow, !page.rows.isEmpty {
                presentation = CandidatePresentation(
                    candidates: preferences.readingHints ? page.rows : page.rows.map { var c = $0; c.annotation = nil; return c },
                    highlightedIndex: page.highlight,
                    page: list.page,
                    hasPreviousPage: page.hasPrevious,
                    hasNextPage: page.hasNext,
                    isPrediction: state.phase == .composing && engine.traits.hasConversionPhase
                )
            }
        }
        display = SessionDisplay(mode: mode, segments: segments, caret: caret, candidates: presentation)
        client?.setMarkedText(segments, caret: caret)
        onChange?(self)
    }
}
