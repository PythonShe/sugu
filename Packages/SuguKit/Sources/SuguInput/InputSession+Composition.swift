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
        if readsVocabulary {
            readsVocabulary = false
            vocabulary = readVocabulary()
        }
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
            commitConverted(engine)
        }
        if let rest = active, !rest.state.isEmpty { cancelComposition() }
    }

    /// Commits the conversion, or the kana typed when there is none, in
    /// katakana while Japanese types katakana.
    func commitConverted(_ engine: any CompositionEngine) {
        guard showsKatakana(engine.state), let raw = engine.commitRaw() else {
            commit(engine.commitConverted())
            return
        }
        commit(Commit(text: WidthConversion.katakana(raw.text), reading: raw.reading))
    }

    /// Whether the composition is kana still being typed, which shows in
    /// katakana while Japanese types katakana.
    func showsKatakana(_ state: CompositionState) -> Bool {
        typesKatakana && mode == .japanese && state.phase == .composing && !state.isEmpty
            && state.segments.allSatisfy { $0.role == .input }
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
            commitWhole(transformed)
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
            // Shown in the script in use; the store finds the word in any.
            let learns = engine.traits.learnsCommits
            commitWhole(candidate.text, word: candidate.text, learn: learns, undoable: learns)
        case .chineseForm:
            // A Chinese name in Japanese text does not belong in the Japanese store.
            commitWhole(candidate.text, undoable: true)
        case .computed:
            // Dates, numerals and results are made fresh each time; learning
            // them would pin yesterday's date to the reading.
            commitWhole(candidate.text, undoable: engine.traits.learnsCommits)
        case .latin:
            commitWhole(candidate.text)
        case .model(let learns):
            // A model conversion the user chose is theirs to keep; a
            // translation is not a reading of what was typed.
            let teaches = learns && engine.traits.learnsCommits
            commitWhole(candidate.text, word: candidate.text, learn: teaches, undoable: teaches)
        }
    }

    /// Commits `text` for the whole composition, which the engine drops:
    /// one of Sugu's own candidates, or a form of the input. `word` is what
    /// the commit teaches as a word of the reading.
    func commitWhole(_ text: String, word: String? = nil, learn: Bool = false, undoable: Bool = false) {
        guard let engine = active else { return }
        let reading = engine.state.reading
        engine.clear()
        let record = word.map { Commit(text: $0, reading: reading, clauses: [.init(reading: reading, text: $0)]) }
        commitText(text, reading: reading, learn: learn, record: record, undoable: undoable)
    }

    /// Forgets the highlighted candidate as a learned word, as ⌃⌦ takes a
    /// word out of Google's and ATOK's history: its learned uses in this
    /// mode go, words the user added or pinned stay. False when it is no
    /// learned word.
    func forgetHighlighted() -> Bool {
        guard let candidate = list.highlighted, let store else { return false }
        let shown = candidate.text
        let ids = store.words(showing: shown, mode: mode)
            .filter { $0.kind == .learned && !$0.pinned }
            .map(\.id)
        guard !ids.isEmpty else { return false }
        store.delete(ids: ids)
        engines.learnedWordsDidChange()
        forgotten.insert(shown)
        undoable = nil
        refresh()
        return true
    }

    func commit(_ commit: Commit?) {
        guard let commit else { refresh(); return }
        let learns = active?.traits.learnsCommits ?? false
        commitText(commit.text, reading: commit.reading, learn: learns, record: commit, undoable: learns)
    }

    func commitText(_ text: String, reading: String, learn: Bool, record: Commit? = nil, undoable: Bool = false) {
        let engine = active
        let typed = engine.map { $0.state.isEmpty ? composedTyped : $0.state.typedText } ?? ""
        endSuggestions()
        active?.clear()
        active = nil
        transformed = nil
        list.clear()
        showsConversionWindow = false
        let record = withContext(record ?? Commit(text: text, reading: reading))
        insertCommitted(text)
        let learned = learn && self.learn(record)
        self.undoable = undoable ? engine.map { PendingUndo(text: text, commit: record, engine: $0, mode: mode, learned: learned) } : nil
        let typedAsRomaji = mode == .japanese && !typed.isEmpty && typed != text && typed.unicodeScalars.allSatisfy { (0x21...0x7E).contains($0.value) }
        retypable = typedAsRomaji ? Retypable(text: text, romaji: typed, commit: record, learned: learned, isRomaji: false) : nil
        publish()
    }

    /// Puts committed text into the field and notes it as what the caret
    /// follows and as part of the field's vocabulary.
    private func insertCommitted(_ text: String) {
        client?.commit(text)
        noteTyped(text)
        if !vocabulary.isEmpty {
            vocabulary = String((vocabulary + text).suffix(Self.vocabularyLimit * 2))
        }
    }

    /// The commit with the text Sugu typed before it, which its n-grams are
    /// learned after, while those are learned.
    private func withContext(_ commit: Commit) -> Commit {
        var commit = commit
        commit.context = preferences.learnsPhrases ? typedBefore : nil
        return commit
    }

    /// Teaches the store a commit, where this field and mode learn;
    /// returns whether it did.
    private func learn(_ record: Commit) -> Bool {
        guard mode != .english, !isSecureInput, let client, preferences.learns(in: client.bundleIdentifier), let store else { return false }
        store.learn(record, mode: mode, script: mode == .chinese ? chineseScript : nil)
        engines.learnedWordsDidChange()
        return true
    }

    /// Commits the start of a composition that goes on (a long Zhuyin
    /// sentence); the field shows the rest as marked text next.
    func commitHead(_ head: Commit) {
        let head = withContext(head)
        insertCommitted(head.text)
        if active?.traits.learnsCommits == true { _ = learn(head) }
        undoable = nil
        retypable = nil
        // Part of the composition is in the field: Esc no longer puts the
        // reconverted selection back.
        reconverted = nil
    }

    /// 英数 pressed twice retypes the Japanese just committed as the romaji
    /// typed for it, and かな twice turns that back, as in Apple's Japanese
    /// input. Replaces only what is still left of the caret.
    /// Returns whether there was a commit to retype.
    public func retypeLastCommit(asRomaji: Bool) -> Bool {
        guard let retypable, retypable.isRomaji != asRomaji, isEmpty, canEditCommitted, let client else { return false }
        let shown = retypable.isRomaji ? retypable.romaji : retypable.text
        let replacement = retypable.isRomaji ? retypable.text : retypable.romaji
        guard client.textBeforeCaret(limit: shown.count) == shown,
              client.deleteBeforeCaret(count: shown.count) else { return false }
        client.commit(replacement)
        noteDeleted(shown.count)
        noteTyped(replacement)
        // The Japanese was not meant; neither was what it taught.
        if retypable.learned, let store {
            if asRomaji { store.unlearn(retypable.commit, mode: .japanese) } else { store.learn(retypable.commit, mode: .japanese) }
            engines.learnedWordsDidChange()
        }
        var next = retypable
        next.isRomaji = asRomaji
        self.retypable = next
        return true
    }

    /// Restores the last commit as a composition with its candidates open.
    /// Deletes only when the text left of the caret is still exactly what
    /// was committed, so a field that moved the caret loses nothing.
    func undoLastCommit() -> Bool {
        guard let undoable, undoable.mode == mode, canEditCommitted, let client else { return false }
        let text = undoable.text
        guard client.textBeforeCaret(limit: text.count) == text,
              client.deleteBeforeCaret(count: text.count) else { return false }
        noteDeleted(text.count)
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
    /// Returns whether there was a selection to reconvert.
    @discardableResult
    public func reconvertSelection() -> Bool {
        guard mode != .english, isEmpty, canReadField, let client, let selected = client.selectedText(), !selected.isEmpty,
              let engine = engines.engine(for: mode) else { return false }
        let reading: String
        if mode == .japanese {
            reading = WidthConversion.hiragana(selected).isHiraganaReading ? WidthConversion.hiragana(selected) : (store?.reading(for: selected, mode: mode) ?? selected)
        } else {
            // A word learned with the other keyboard has a reading this one
            // cannot type: codes with tones for Zhuyin, letters for pinyin.
            let learned = store?.reading(for: selected, mode: mode).flatMap { reading in
                typesZhuyin == (Zhuyin.syllables(ofCodes: reading) != nil) ? reading : nil
            }
            guard let known = learned ?? engines.chineseReading(of: selected) else { return false }
            reading = known
        }
        active = engine
        reconverted = selected
        engine.clear()
        engine.restore(reading: reading)
        showsConversionWindow = true
        refresh()
        return true
    }
}

/// A word to add by hand, from the selected text.
public struct WordDraft: Sendable, Equatable {
    public var text: String
    /// The reading Sugu knows for it, as a word is entered; empty when
    /// none is known.
    public var reading: String
    public var mode: InputMode
}

extension InputSession {
    /// The selected text as a word to add, in the language being typed or
    /// else the first enabled one: its reading the one it was learned
    /// with, the kana themselves, or the dictionary's pinyin.
    public func selectedWordDraft() -> WordDraft {
        let mode = mode != .english ? mode : (preferences.enabledModes.first { $0 != .english } ?? .chinese)
        guard isEmpty, canReadField, let selected = client?.selectedText()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selected.isEmpty, selected.count <= LearnedStore.maximumWordLength else {
            return WordDraft(text: "", reading: "", mode: mode)
        }
        let learned = store?.reading(for: selected, mode: mode)
        let reading: String?
        switch mode {
        case .japanese:
            let kana = WidthConversion.hiragana(selected)
            reading = kana.isHiraganaReading ? kana : learned
        default:
            // A Zhuyin word's reading is its codes; pinyin is entered here.
            reading = learned.flatMap { Zhuyin.syllables(ofCodes: $0) == nil ? $0 : nil } ?? engines.pinyin(of: selected)
        }
        return WordDraft(text: selected, reading: reading ?? "", mode: mode)
    }
}

/// A Japanese commit and the romaji typed for it, either of which the
/// field shows.
struct Retypable {
    var text: String
    var romaji: String
    var commit: Commit
    var learned: Bool
    /// The field shows the romaji.
    var isRomaji: Bool
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
