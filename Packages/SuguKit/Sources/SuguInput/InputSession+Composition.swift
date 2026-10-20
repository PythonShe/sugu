import Foundation
import SuguCore
import SuguLearning

extension InputSession {
    // MARK: Composition lifecycle

    /// Hands the letters typed while the engine was set up over to it,
    /// with the caret where it was and any F9/F10 form still shown.
    func engineBecameReady(_ mode: InputMode) {
        guard mode == self.mode, active === loading, let engine = engines.engine(for: mode) else { return }
        let waiting = loading.state
        let shownForm = transformed
        begin(with: engine, input: waiting.reading)
        // Zhuyin keys are not one character each; its caret stays at the end.
        let caretFromEnd = engine.traits.composition == .live ? waiting.reading.count - waiting.caret : 0
        if caretFromEnd > 0 {
            for _ in 0..<caretFromEnd { engine.moveCaret(.left) }
            refresh()
        }
        if let shownForm {
            transformed = shownForm
            publish()
        }
    }

    func begin(with engine: any CompositionEngine, input: String) {
        active = engine
        engine.clear()
        transformed = nil
        list.setHighlight(nil)
        showsConversionWindow = false
        context = readContext()
        engine.setLeftContext(context)
        engine.insert(input)
        refresh()
    }

    /// Commits what the composition shows, as when focus leaves or a mode
    /// changes.
    public func commitComposition() {
        guard let engine = active, !engine.state.isEmpty else { return }
        if transformed != nil {
            commitHighlighted()
            return
        }
        if composition(of: engine) == .sentence {
            commit(engine.commitConverted() ?? engine.commitRaw())
        } else if composition(of: engine) == .live {
            commitHighlighted()
            // A partial selection (a phrase for the first syllables) leaves
            // the rest composing; focus is leaving, so commit all of it.
            if let rest = active, !rest.state.isEmpty {
                commit(rest.commitConverted() ?? rest.commitRaw())
            }
        } else if list.highlight != nil, engine.state.phase != .converting || highlightsOwnCandidate {
            // A highlighted prediction is what the field shows.
            commitHighlighted()
        } else {
            commit(engine.commitConverted())
        }
        if let rest = active, !rest.state.isEmpty { cancelComposition() }
    }

    public func cancelComposition() {
        endSuggestions()
        active?.clear()
        active = nil
        transformed = nil
        list.clear()
        client?.setMarkedText([], caret: 0)
        publish()
    }

    /// Whether the highlight is on one of Sugu's candidates (learned,
    /// computed, a Chinese form) rather than the engine's.
    var highlightsOwnCandidate: Bool {
        list.highlighted.map { $0.engineIndex == nil } ?? false
    }

    /// Commits the highlighted candidate, or the composition when no
    /// candidate is highlighted.
    func commitHighlighted() {
        guard let engine = active else { return }
        if let transformed {
            let reading = engine.state.reading
            engine.clear()
            commitText(transformed, reading: reading, learn: false)
            return
        }
        guard let index = list.highlight ?? (composition(of: engine) == .live ? 0 : nil),
              list.candidates.indices.contains(index) else {
            commit(engine.commitConverted() ?? engine.commitRaw())
            return
        }
        select(list.candidates[index])
    }

    /// Chooses a candidate on the current page (0-based row), as a click
    /// or number key does.
    public func selectCandidate(onPage row: Int) {
        guard let index = list.index(onPage: row) else { return }
        select(list.candidates[index])
    }

    func selectOnPage(_ digit: Int) {
        selectCandidate(onPage: digit == 0 ? 9 : digit - 1)
    }

    func select(_ candidate: Candidate) {
        guard let engine = active else { return }
        switch candidate.source {
        case .engine(let index):
            switch engine.select(index) {
            case .committed(let commit): self.commit(commit)
            case .continued:
                list.highlight = nil
                refresh()
            }
        case .learned:
            // Shown in the script in use; the store keeps the form it learned.
            let reading = engine.state.reading
            let learned = learnedText(shown: candidate.text, reading: reading)
            let record = Commit(text: learned, reading: reading, clauses: [.init(reading: reading, text: learned)])
            let learns = engine.traits.learnsCommits
            engine.clear()
            commitText(candidate.text, reading: reading, learn: learns, record: record, undoable: learns)
        case .chineseForm:
            // A Chinese name in Japanese text does not belong in the Japanese store.
            let reading = engine.state.reading
            engine.clear()
            commitText(candidate.text, reading: reading, learn: false, undoable: true)
        case .computed:
            // Dates, numerals and results are made fresh each time; learning
            // them would pin yesterday's date to the reading.
            let reading = engine.state.reading
            let record = Commit(text: candidate.text, reading: reading)
            engine.clear()
            commitText(candidate.text, reading: reading, learn: false, record: record, undoable: engine.traits.learnsCommits)
        case .latin:
            let reading = engine.state.reading
            engine.clear()
            commitText(candidate.text, reading: reading, learn: false)
        case .model(let learns):
            // A model conversion the user chose is theirs to keep; a
            // translation is not a reading of what was typed.
            let reading = engine.state.reading
            let teaches = learns && engine.traits.learnsCommits
            let record = Commit(text: candidate.text, reading: reading, clauses: [.init(reading: reading, text: candidate.text)])
            engine.clear()
            commitText(candidate.text, reading: reading, learn: teaches, record: record, undoable: teaches)
        }
    }

    /// The learned word a candidate shows, before script conversion.
    private func learnedText(shown: String, reading: String) -> String {
        guard mode == .chinese, let words = store?.lookup(reading, mode: mode) else { return shown }
        return words.first { $0.text == shown }?.text
            ?? words.first { engines.chineseText($0.text) == shown }?.text
            ?? shown
    }

    func commit(_ commit: Commit?) {
        guard let commit else { refresh(); return }
        let learns = active?.traits.learnsCommits ?? false
        commitText(commit.text, reading: commit.reading, learn: learns, record: commit, undoable: learns)
    }

    func commitText(_ text: String, reading: String, learn: Bool, record: Commit? = nil, undoable: Bool = false) {
        let engine = active
        endSuggestions()
        active?.clear()
        active = nil
        transformed = nil
        list.clear()
        showsConversionWindow = false
        client?.commit(text)
        lastTyped = text.last
        if !vocabulary.isEmpty {
            vocabulary = String((vocabulary + text).suffix(Self.vocabularyLimit * 2))
        }
        let record = record ?? Commit(text: text, reading: reading)
        var learned = false
        if learn, mode != .english, !isSecureInput, let client, preferences.learns(in: client.bundleIdentifier), let store {
            store.learn(record, mode: mode)
            engines.learnedWordsDidChange()
            learned = true
        }
        self.undoable = undoable ? engine.map { PendingUndo(text: text, commit: record, engine: $0, mode: mode, learned: learned) } : nil
        publish()
    }

    /// Restores the last commit as a composition with its candidates open.
    /// Deletes only when the text left of the caret is still exactly what
    /// was committed, so a field that moved the caret loses nothing.
    func undoLastCommit() -> Bool {
        guard let undoable, undoable.mode == mode, canReadField, let client else { return false }
        let text = undoable.text
        guard client.textBeforeCaret(limit: text.count) == text,
              client.deleteBeforeCaret(count: text.count) else { return false }
        self.undoable = nil
        // The commit was a mistake; so was what it taught.
        if undoable.learned, let store {
            store.unlearn(undoable.commit, mode: undoable.mode)
            engines.learnedWordsDidChange()
        }
        let engine = undoable.engine
        active = engine
        engine.clear()
        engine.restore(reading: undoable.commit.reading)
        showsConversionWindow = true
        refresh()
        return true
    }

    /// Reconverts the selected text in fields that expose it: the selection
    /// becomes a composition of its reading, the one it was learned with or
    /// else the dictionary's.
    public func reconvertSelection() {
        guard mode != .english, isEmpty, canReadField, let client, let selected = client.selectedText(), !selected.isEmpty,
              let engine = engines.engine(for: mode) else { return }
        let reading: String
        if mode == .japanese {
            reading = WidthConversion.hiragana(selected).isHiraganaReading ? WidthConversion.hiragana(selected) : (store?.reading(for: selected, mode: mode) ?? selected)
        } else {
            guard let known = store?.reading(for: selected, mode: mode) ?? engines.chineseReading(of: selected) else { return }
            reading = known
        }
        active = engine
        engine.clear()
        engine.restore(reading: reading)
        showsConversionWindow = true
        refresh()
    }
}

/// The commit ⌃⌫ can take back.
struct PendingUndo {
    /// What was inserted into the field.
    var text: String
    /// What was learned, and the reading to restore.
    var commit: Commit
    /// The engine that composed it, which the reading goes back into.
    var engine: any CompositionEngine
    var mode: InputMode
    var learned: Bool
}
