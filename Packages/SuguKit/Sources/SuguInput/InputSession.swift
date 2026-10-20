import Foundation
import SuguCore
import SuguLearning

/// Supplies engines to the session. Engines load lazily on first use of
/// their mode; `nil` means the engine is not ready yet.
@MainActor
public protocol EngineSource: AnyObject {
    func engine(for mode: InputMode) -> (any CompositionEngine)?
    /// Called after the learned store changed through a commit, so engines
    /// that take user words (AzooKey) can refresh them.
    func learnedWordsDidChange()
    /// The Chinese characters to produce: the global choice or the focused
    /// app's.
    func setChineseScript(_ script: ChineseScript)
    /// Chinese text in the script in use, for candidates that do not come
    /// from librime; nil when it cannot be converted.
    func chineseText(_ text: String) -> String?
}

/// Remembers the last mode per app across launches.
@MainActor
public protocol ModeMemory: AnyObject {
    func mode(for bundleIdentifier: String) -> InputMode?
    func remember(_ mode: InputMode, for bundleIdentifier: String)
}

/// Sugu's input state machine. Platform-free: the shell turns events into
/// `KeyInput`, calls `handle(_:)`, and renders `display` whenever
/// `onChange` fires. One session serves every client; focus changes attach
/// a different client.
@MainActor
public final class InputSession {
    public private(set) var mode: InputMode
    public private(set) var display: SessionDisplay
    public var preferences: Preferences {
        didSet { applyPreferences() }
    }
    /// Secure input (password fields): everything passes through, nothing
    /// is read or learned.
    public var isSecureInput = false {
        didSet { if isSecureInput, !isEmpty { cancelComposition() } }
    }
    /// Called after every change to `display` or `mode`.
    public var onChange: ((InputSession) -> Void)?
    /// Called when the mode changes, with whether the user switched it.
    public var onModeChange: ((InputMode) -> Void)?

    private let engines: any EngineSource
    private let store: LearnedStore?
    private let modeMemory: (any ModeMemory)?
    private var assembler: CandidateAssembler
    private let expression: ExpressionEngine

    private weak var client: (any InputClient)?
    private var lastCJKMode: InputMode
    /// The engine composing right now (a language engine or the `v`
    /// expression engine).
    private var active: (any CompositionEngine)?
    private var candidates: [Candidate] = []
    private var highlight: Int?
    private var page = 0
    /// Japanese shows the candidate window from the second conversion key.
    private var showsConversionWindow = false
    /// Text a function key (F6–F10) turned the composition into.
    private var transformed: String?
    private var punctuator = ChinesePunctuator()
    private var context = ""
    /// The field's text around the caret when it gained focus, plus what was
    /// committed since: its words rank first while the field has focus
    /// (document vocabulary). Kept in memory only.
    private var vocabulary = ""
    /// The commit ⌃⌫ can take back, with the engine that composed it.
    private var undoable: (text: String, commit: Commit, engine: any CompositionEngine, mode: InputMode, learned: Bool)?

    public init(
        preferences: Preferences,
        engines: any EngineSource,
        store: LearnedStore?,
        modeMemory: (any ModeMemory)? = nil,
        latin: LatinInference? = nil,
        computed: ComputedCandidates = ComputedCandidates()
    ) {
        self.preferences = preferences
        self.engines = engines
        self.store = store
        self.modeMemory = modeMemory
        self.assembler = CandidateAssembler(computed: computed, latin: latin, store: store)
        self.expression = ExpressionEngine(computed: computed)
        let initial = preferences.enabledModes.first { $0 != .english } ?? .english
        self.mode = initial
        self.lastCJKMode = initial == .english ? .chinese : initial
        self.display = .idle(initial)
        applyPreferences()
    }

    public var isEmpty: Bool { active?.state.isEmpty ?? true }

    private func applyPreferences() {
        punctuator.width = preferences.punctuationWidth
        if var latin = assembler.latin {
            latin.allowList = Set(preferences.latinAllowList.map { $0.lowercased() })
            assembler.latin = latin
        }
        if !preferences.enabledModes.contains(mode) {
            setMode(preferences.enabledModes.first ?? .english)
        }
        engines.setChineseScript(chineseScript)
        // Candidates on screen follow a script change at once.
        if active != nil { refresh() }
    }

    /// The focused app's Chinese script, or the global one.
    private var chineseScript: ChineseScript {
        preferences.rule(for: client?.bundleIdentifier).chineseScript ?? preferences.chineseScript
    }

    // MARK: Clients

    /// Attaches the focused field. Applies the app's mode rule.
    public func attach(_ client: any InputClient) {
        if self.client !== client, !isEmpty { commitComposition() }
        self.client = client
        punctuator.reset()
        undoable = nil
        vocabulary = readVocabulary()
        let bundleID = client.bundleIdentifier
        let rule = preferences.rule(for: bundleID)
        engines.setChineseScript(chineseScript)
        if let mode = rule.defaultMode {
            setMode(mode, remember: false)
        } else if preferences.rememberModePerApp, let bundleID, let remembered = modeMemory?.mode(for: bundleID) {
            setMode(remembered, remember: false)
        }
        publish()
    }

    /// Detaches a field that lost focus, committing what is composed.
    public func detach(_ client: any InputClient) {
        guard self.client === client else { return }
        if !isEmpty { commitComposition() }
        self.client = nil
        vocabulary = ""
    }

    // MARK: Modes

    public func setMode(_ newMode: InputMode, remember: Bool = true) {
        guard preferences.enabledModes.contains(newMode) || newMode == .english else { return }
        if newMode != mode, !isEmpty { commitComposition() }
        let changed = newMode != mode
        mode = newMode
        if newMode != .english { lastCJKMode = newMode }
        if remember, preferences.rememberModePerApp, let bundleID = client?.bundleIdentifier {
            modeMemory?.remember(newMode, for: bundleID)
        }
        publish()
        if changed { onModeChange?(newMode) }
    }

    /// English ↔ the last Chinese or Japanese mode.
    public func toggleEnglish() {
        setMode(mode == .english ? lastCJKMode : .english)
    }

    /// Chinese ↔ Japanese, when both are enabled.
    public func switchCJKMode() {
        let cjk = preferences.enabledModes.filter { $0 != .english }
        guard cjk.count > 1 else { setMode(cjk.first ?? .english); return }
        let current = mode == .english ? lastCJKMode : mode
        let next = cjk[(cjk.firstIndex(of: current).map { $0 + 1 } ?? 0) % cjk.count]
        setMode(next)
    }

    // MARK: Keys

    /// Handles one key press. Returns true when Sugu consumed it.
    public func handle(_ key: KeyInput) -> Bool {
        if isSecureInput { return false }
        let isUndoKey = key.modifiers.contains(.control) && key.keyCode == VirtualKey.delete
        // Undo applies only to the commit just made; any other key ends it.
        let pendingUndo = undoable
        undoable = nil
        if isUndoKey, isEmpty {
            undoable = pendingUndo
            return undoLastCommit()
        }

        switch key.keyCode {
        case VirtualKey.kana where preferences.enabledModes.contains(.japanese):
            setMode(.japanese); return true
        case VirtualKey.eisu:
            setMode(.english); return true
        default:
            break
        }
        if key.modifiers.contains(.control), key.modifiers.contains(.shift), key.keyCode == VirtualKey.space {
            switchCJKMode()
            return true
        }
        if key.isShortcut {
            // Shortcuts belong to the app; finish the composition first.
            if !isEmpty { commitComposition() }
            return false
        }
        if key.keyCode == VirtualKey.escape, preferences.rule(for: client?.bundleIdentifier).escapeSwitchesToEnglish {
            if !isEmpty { cancelComposition() }
            setMode(.english)
            return false
        }
        if !isEmpty, let consumed = handleFunctionKey(key) { return consumed }

        switch mode {
        case .english: return false
        case .chinese: return handleChinese(key)
        case .japanese: return handleJapanese(key)
        }
    }

    // MARK: Chinese

    private func handleChinese(_ key: KeyInput) -> Bool {
        let character = key.printable
        if key.modifiers.contains(.option) {
            if !isEmpty { commitComposition() }
            return false
        }
        if isEmpty {
            guard let character, !key.modifiers.contains(.numericPad) else { return false }
            if character == ComputedCandidates.chineseNumberPrefix {
                begin(with: expression, input: String(character))
                return true
            }
            if character.isASCIILowercaseLetter, let engine = engines.engine(for: .chinese) {
                begin(with: engine, input: String(character))
                return true
            }
            if ChinesePunctuator.handles(character) {
                let previous = lastCharacterBeforeCaret()
                commitText(punctuator.output(for: character, after: previous), reading: String(character), learn: false)
                return true
            }
            return false
        }
        guard let engine = active else { return false }

        switch key.keyCode {
        case VirtualKey.escape: cancelComposition(); return true
        case VirtualKey.returnKey, VirtualKey.keypadEnter: commit(engine.commitRaw()); return true
        case VirtualKey.space: commitHighlighted(); return true
        case VirtualKey.delete: engine.deleteBackward(); refresh(); return true
        case VirtualKey.forwardDelete: engine.deleteForward(); refresh(); return true
        case VirtualKey.home: engine.moveCaret(.start); refresh(); return true
        case VirtualKey.end: engine.moveCaret(.end); refresh(); return true
        case VirtualKey.pageUp: turnPage(by: -1); return true
        case VirtualKey.pageDown: turnPage(by: 1); return true
        case VirtualKey.tab: moveHighlight(by: key.modifiers.contains(.shift) ? -1 : 1); return true
        case VirtualKey.up: verticalLayout ? moveHighlight(by: -1) : turnPage(by: -1); return true
        case VirtualKey.down: verticalLayout ? moveHighlight(by: 1) : turnPage(by: 1); return true
        case VirtualKey.left:
            if verticalLayout { engine.moveCaret(.left); refresh() } else { moveHighlight(by: -1) }
            return true
        case VirtualKey.right:
            if verticalLayout { engine.moveCaret(.right); refresh() } else { moveHighlight(by: 1) }
            return true
        default:
            break
        }
        guard let character else { return true }
        if engine is ExpressionEngine, engine.accepts(character) {
            engine.insert(String(character))
            refresh()
            return true
        }
        if key.modifiers.contains(.numericPad) {
            commitComposition()
            return false
        }
        if let digit = character.selectionDigit {
            selectOnPage(digit)
            return true
        }
        if character == "-" && !(engine is ExpressionEngine) { turnPage(by: -1); return true }
        if character == "=" && !(engine is ExpressionEngine) { turnPage(by: 1); return true }
        if engine.accepts(character) {
            engine.insert(String(character))
            refresh()
            return true
        }
        if ChinesePunctuator.handles(character) {
            commitHighlighted()
            let previous = lastCharacterBeforeCaret()
            commitText(punctuator.output(for: character, after: previous), reading: String(character), learn: false)
            return true
        }
        // Anything else: finish the composition and let the key through.
        commitHighlighted()
        return false
    }

    // MARK: Japanese

    private func handleJapanese(_ key: KeyInput) -> Bool {
        let character = key.printable
        if key.modifiers.contains(.option) {
            if !isEmpty { commitComposition() }
            return false
        }
        if isEmpty {
            if key.keyCode == VirtualKey.space, preferences.fullWidthSpace, !key.modifiers.contains(.shift) {
                commitText("　", reading: " ", learn: false)
                return true
            }
            guard let character, !key.modifiers.contains(.numericPad), let engine = engines.engine(for: .japanese),
                  engine.accepts(character) else { return false }
            begin(with: engine, input: japaneseInput(for: character))
            return true
        }
        guard let engine = active else { return false }
        let converting = engine.state.phase == .converting

        switch key.keyCode {
        case VirtualKey.escape:
            if transformed != nil { transformed = nil; publish() } else if converting { engine.cancelConversion(); refresh() } else { cancelComposition() }
            return true
        case VirtualKey.returnKey, VirtualKey.keypadEnter:
            if transformed != nil || (highlight != nil && (!converting || highlightsOwnCandidate)) {
                commitHighlighted()
            } else {
                commit(engine.commitConverted())
            }
            return true
        case VirtualKey.space:
            transformed = nil
            if converting {
                showsConversionWindow = true
                moveHighlight(by: key.modifiers.contains(.shift) ? -1 : 1)
            } else {
                highlight = nil
                engine.convert()
                refresh()
            }
            return true
        case VirtualKey.delete:
            transformed = nil
            if converting { engine.cancelConversion() } else { engine.deleteBackward() }
            refresh()
            return true
        case VirtualKey.forwardDelete:
            transformed = nil
            engine.deleteForward(); refresh(); return true
        case VirtualKey.left, VirtualKey.right:
            let forward = key.keyCode == VirtualKey.right
            if converting {
                if key.modifiers.contains(.shift) { engine.resizeFocus(by: forward ? 1 : -1) } else { engine.moveFocus(forward: forward) }
            } else {
                engine.moveCaret(forward ? .right : .left)
            }
            refresh()
            return true
        case VirtualKey.up, VirtualKey.down, VirtualKey.tab:
            let backward = key.keyCode == VirtualKey.up || (key.keyCode == VirtualKey.tab && key.modifiers.contains(.shift))
            if converting {
                showsConversionWindow = true
                moveHighlight(by: backward ? -1 : 1)
            } else if !candidates.isEmpty {
                // Step into the predictions.
                if highlight == nil { highlight = backward ? candidates.count - 1 : 0; publish() } else { moveHighlight(by: backward ? -1 : 1) }
            }
            return true
        case VirtualKey.pageUp: turnPage(by: -1); return true
        case VirtualKey.pageDown: turnPage(by: 1); return true
        case VirtualKey.home: if !converting { engine.moveCaret(.start); refresh() }; return true
        case VirtualKey.end: if !converting { engine.moveCaret(.end); refresh() }; return true
        default:
            break
        }
        guard let character else { return true }
        // Numpad keys type numbers; they never select.
        if key.modifiers.contains(.numericPad) {
            commitComposition()
            return false
        }
        let windowShown = converting ? showsConversionWindow : highlight != nil
        if windowShown, let digit = character.selectionDigit {
            selectOnPage(digit)
            return true
        }
        if engine.accepts(character) {
            if converting || transformed != nil || highlight != nil {
                commitComposition()
                guard let fresh = engines.engine(for: .japanese) else { return true }
                begin(with: fresh, input: japaneseInput(for: character))
                return true
            }
            engine.insert(japaneseInput(for: character))
            refresh()
            return true
        }
        commitComposition()
        return false
    }

    /// Romaji input maps symbol keys to Japanese symbols; kana input
    /// passes keys through to the kana table.
    private func japaneseInput(for character: Character) -> String {
        preferences.kanaInput ? String(character) : preferences.japanesePunctuation.romajiInput(for: character)
    }

    // MARK: Function keys (F6–F10)

    private func handleFunctionKey(_ key: KeyInput) -> Bool? {
        guard let state = active?.state else { return nil }
        let kana = state.reading
        let typed = state.typedText
        let text: String?
        switch key.keyCode {
        case VirtualKey.f6: text = mode == .japanese ? WidthConversion.hiragana(kana) : nil
        case VirtualKey.f7: text = mode == .japanese ? WidthConversion.katakana(kana) : nil
        case VirtualKey.f8: text = mode == .japanese ? WidthConversion.halfWidthKatakana(kana) : nil
        case VirtualKey.f9: text = WidthConversion.fullWidth(typed)
        case VirtualKey.f10: text = typed
        default: return nil
        }
        guard let text else { return nil }
        transformed = text
        highlight = nil
        publish()
        return true
    }

    // MARK: Composition lifecycle

    private func begin(with engine: any CompositionEngine, input: String) {
        active = engine
        engine.clear()
        transformed = nil
        highlight = nil
        page = 0
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
        if mode == .chinese || engine is ExpressionEngine {
            commitHighlighted()
            // A partial selection (a phrase for the first syllables) leaves
            // the rest composing; focus is leaving, so commit all of it.
            if let rest = active, !rest.state.isEmpty {
                commit(rest.commitConverted() ?? rest.commitRaw())
            }
        } else if highlight != nil, engine.state.phase != .converting || highlightsOwnCandidate {
            // A highlighted prediction is what the field shows.
            commitHighlighted()
        } else {
            commit(engine.commitConverted())
        }
        if let rest = active, !rest.state.isEmpty { cancelComposition() }
    }

    public func cancelComposition() {
        active?.clear()
        active = nil
        transformed = nil
        candidates = []
        highlight = nil
        client?.setMarkedText([], caret: 0)
        publish()
    }

    /// Whether the highlight is on one of Sugu's candidates (learned,
    /// computed, a Chinese form) rather than the engine's.
    private var highlightsOwnCandidate: Bool {
        guard let highlight, candidates.indices.contains(highlight) else { return false }
        return candidates[highlight].engineIndex == nil
    }

    /// Commits the highlighted candidate, or the composition when no
    /// candidate is highlighted.
    private func commitHighlighted() {
        guard let engine = active else { return }
        if let transformed {
            let reading = engine.state.reading
            engine.clear()
            commitText(transformed, reading: reading, learn: false)
            return
        }
        guard let index = highlight ?? (mode == .chinese || engine is ExpressionEngine ? 0 : nil),
              candidates.indices.contains(index) else {
            commit(engine.commitConverted() ?? engine.commitRaw())
            return
        }
        select(candidates[index])
    }

    /// Chooses a candidate on the current page (0-based row), as a click
    /// or number key does.
    public func selectCandidate(onPage row: Int) {
        let index = page * pageSize + row
        guard candidates.indices.contains(index) else { return }
        select(candidates[index])
    }

    private func selectOnPage(_ digit: Int) {
        let row = digit == 0 ? 9 : digit - 1
        guard row < pageSize else { return }
        selectCandidate(onPage: row)
    }

    private func select(_ candidate: Candidate) {
        guard let engine = active else { return }
        switch candidate.source {
        case .engine(let index):
            switch engine.select(index) {
            case .committed(let commit): self.commit(commit)
            case .continued:
                highlight = nil
                refresh()
            }
        case .learned:
            // Shown in the script in use; the store keeps the form it learned.
            let reading = engine.state.reading
            let learned = learnedText(shown: candidate.text, reading: reading)
            let record = Commit(text: learned, reading: reading, clauses: [.init(reading: reading, text: learned)])
            let fromLanguage = !(engine is ExpressionEngine)
            engine.clear()
            commitText(candidate.text, reading: reading, learn: fromLanguage, record: record, undoable: fromLanguage)
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
            commitText(candidate.text, reading: reading, learn: false, record: record, undoable: !(engine is ExpressionEngine))
        case .latin:
            let reading = engine.state.reading
            engine.clear()
            commitText(candidate.text, reading: reading, learn: false)
        }
    }

    /// The learned word a candidate shows, before script conversion.
    private func learnedText(shown: String, reading: String) -> String {
        guard mode == .chinese, let words = store?.lookup(reading, mode: mode) else { return shown }
        return words.first { $0.text == shown }?.text
            ?? words.first { engines.chineseText($0.text) == shown }?.text
            ?? shown
    }

    private func commit(_ commit: Commit?) {
        guard let commit else { refresh(); return }
        // Expressions are neither learned nor restorable into an engine.
        let fromLanguage = !(active is ExpressionEngine)
        commitText(commit.text, reading: commit.reading, learn: fromLanguage, record: commit, undoable: fromLanguage)
    }

    private func commitText(_ text: String, reading: String, learn: Bool, record: Commit? = nil, undoable: Bool = false) {
        let engine = active
        active?.clear()
        active = nil
        transformed = nil
        candidates = []
        highlight = nil
        page = 0
        showsConversionWindow = false
        client?.commit(text)
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
        self.undoable = undoable ? engine.map { (text, record, $0, mode, learned) } : nil
        publish()
    }

    /// Restores the last commit as a composition with its candidates open.
    /// Deletes only when the text left of the caret is still exactly what
    /// was committed, so a field that moved the caret loses nothing.
    private func undoLastCommit() -> Bool {
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
    /// becomes a composition of its reading when Sugu knows one.
    public func reconvertSelection() {
        guard mode != .english, isEmpty, canReadField, let client, let selected = client.selectedText(), !selected.isEmpty,
              let engine = engines.engine(for: mode) else { return }
        let reading: String
        if mode == .japanese {
            reading = WidthConversion.hiragana(selected).isHiraganaReading ? WidthConversion.hiragana(selected) : (store?.reading(for: selected, mode: mode) ?? selected)
        } else {
            guard let known = store?.reading(for: selected, mode: mode) else { return }
            reading = known
        }
        active = engine
        engine.clear()
        engine.restore(reading: reading)
        showsConversionWindow = true
        refresh()
    }

    // MARK: Candidate list

    private var pageSize: Int { max(1, min(10, preferences.candidatesPerPage)) }
    private var verticalLayout: Bool { preferences.candidateLayout == .vertical }

    private func moveHighlight(by delta: Int) {
        guard !candidates.isEmpty else { return }
        let current = highlight ?? (delta > 0 ? -1 : 0)
        let next = min(max(0, current + delta), candidates.count - 1)
        setHighlight(next)
    }

    /// Turns the candidate list by `delta` pages, as the paging keys do.
    public func turnPage(by delta: Int) {
        guard !candidates.isEmpty else { return }
        let pages = (candidates.count + pageSize - 1) / pageSize
        let target = min(max(0, page + delta), pages - 1)
        guard target != page else { return }
        page = target
        if highlight != nil || mode == .chinese {
            setHighlight(target * pageSize)
        } else {
            publish()
        }
    }

    private func setHighlight(_ index: Int) {
        highlight = index
        page = index / pageSize
        if let engine = active, engine.state.phase == .converting, let engineIndex = candidates[index].engineIndex {
            engine.highlight(engineIndex)
            // The focused clause text follows the highlight.
            candidates = assembled(engine.state)
        }
        publish()
    }

    /// Re-reads the engine after a change and rebuilds the list.
    private func refresh() {
        guard let engine = active else { publish(); return }
        if engine.state.isEmpty {
            active = nil
            candidates = []
            highlight = nil
            publish()
            return
        }
        candidates = assembled(engine.state)
        let state = engine.state
        if state.phase == .converting {
            highlight = state.highlightedIndex.flatMap { engineIndex in candidates.firstIndex { $0.engineIndex == engineIndex } } ?? 0
        } else if mode == .chinese || engine is ExpressionEngine {
            highlight = candidates.isEmpty ? nil : 0
        } else {
            highlight = nil
        }
        page = (highlight ?? 0) / pageSize
        publish()
    }

    private func assembled(_ state: CompositionState) -> [Candidate] {
        assembler.assemble(.init(
            mode: active is ExpressionEngine ? .english : mode,
            state: state,
            context: preferences.leftContextRanking ? context : "",
            vocabulary: preferences.leftContextRanking && preferences.documentVocabulary ? vocabulary : "",
            pageSize: pageSize,
            chineseText: { [engines] in engines.chineseText($0) },
            offersChineseForms: preferences.enabledModes.contains(.chinese)
        ))
    }

    private func publish() {
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
                if mode == .japanese, let highlight, candidates.indices.contains(highlight),
                   state.phase == .composing || candidates[highlight].engineIndex == nil {
                    segments = [CompositionSegment(candidates[highlight].text, role: .focused)]
                    caret = candidates[highlight].text.count
                }
            }
            let showWindow: Bool
            if transformed != nil {
                showWindow = false
            } else if state.phase == .converting {
                showWindow = showsConversionWindow
            } else {
                showWindow = mode == .chinese || engine is ExpressionEngine || preferences.japanesePredictions
            }
            if showWindow, !candidates.isEmpty {
                let start = page * pageSize
                let rows = Array(candidates[start..<min(candidates.count, start + pageSize)])
                presentation = CandidatePresentation(
                    candidates: preferences.readingHints ? rows : rows.map { var c = $0; c.annotation = nil; return c },
                    highlightedIndex: highlight.flatMap { $0 >= start && $0 < start + pageSize ? $0 - start : nil },
                    page: page,
                    hasPreviousPage: page > 0,
                    hasNextPage: start + pageSize < candidates.count,
                    isPrediction: state.phase == .composing && mode == .japanese
                )
            }
        }
        display = SessionDisplay(mode: mode, segments: segments, caret: caret, candidates: presentation)
        client?.setMarkedText(segments, caret: caret)
        onChange?(self)
    }

    // MARK: Document context

    /// The one gate for reading the field: never in secure input or in apps
    /// excluded from learning and context.
    private var canReadField: Bool {
        !isSecureInput && preferences.readsContext(in: client?.bundleIdentifier)
    }

    static let contextLimit = 200
    static let vocabularyLimit = 2_000

    private func readContext() -> String {
        guard preferences.leftContextRanking, canReadField else { return "" }
        return client?.textBeforeCaret(limit: Self.contextLimit) ?? ""
    }

    /// Text on both sides of the caret, read once when the field gains
    /// focus rather than on the keystroke path.
    private func readVocabulary() -> String {
        guard preferences.leftContextRanking, preferences.documentVocabulary, canReadField, let client else { return "" }
        let before = client.textBeforeCaret(limit: Self.vocabularyLimit) ?? ""
        let after = client.textAfterCaret(limit: Self.vocabularyLimit) ?? ""
        return before + "\n" + after
    }

    private func lastCharacterBeforeCaret() -> Character? {
        canReadField ? client?.textBeforeCaret(limit: 1)?.last : nil
    }
}

private extension Character {
    /// 1–9 and 0 as candidate selection keys.
    var selectionDigit: Int? {
        guard isASCIIDigitCharacter else { return nil }
        return asciiDigitValue
    }
}
