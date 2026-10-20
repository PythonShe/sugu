import Foundation
import os
import SuguCore
import SuguLearning

/// Supplies engines to the session. Engines are prepared when their mode
/// is entered or a field gains focus; `nil` means not ready yet.
@MainActor
public protocol EngineSource: AnyObject {
    /// The engine for a mode; nil while it is still being set up.
    func engine(for mode: InputMode) -> (any CompositionEngine)?
    /// Starts setting up a mode's engine, so it is ready by the first key.
    func prepare(_ mode: InputMode)
    /// Called when an engine `engine(for:)` returned nil for is ready.
    var onEngineReady: ((InputMode) -> Void)? { get set }
    /// Whether the last attempt to set up a mode's engine failed.
    func isFailing(_ mode: InputMode) -> Bool
    /// Called after the learned store changed through a commit, so engines
    /// that take user words (AzooKey) can refresh them.
    func learnedWordsDidChange()
    /// The Chinese characters to produce: the global choice or the focused
    /// app's.
    func setChineseScript(_ script: ChineseScript)
    /// Chinese text in the script in use, for candidates that do not come
    /// from librime; nil when it cannot be converted.
    func chineseText(_ text: String) -> String?
    /// Keys that type Chinese text, for reconverting text Sugu did not
    /// type; nil when there is no reading.
    func chineseReading(of text: String) -> String?
    /// Chinese text in full pinyin without tones (`nihao`), as a word is
    /// entered by hand; nil when there is no reading.
    func pinyin(of text: String) -> String?
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
    public internal(set) var display: SessionDisplay
    public var preferences: Preferences {
        didSet { applyPreferences() }
    }
    /// Secure input (password fields): everything passes through, nothing
    /// is read or learned.
    public var isSecureInput = false {
        didSet {
            guard isSecureInput != oldValue else { return }
            Log.input.notice("Secure input \(self.isSecureInput ? "on" : "off", privacy: .public)")
            if isSecureInput, !isEmpty { cancelComposition() }
        }
    }
    /// Called after every change to `display` or `mode`.
    public var onChange: ((InputSession) -> Void)?
    /// Called when the mode changes, with whether the user switched it.
    public var onModeChange: ((_ mode: InputMode, _ byUser: Bool) -> Void)?

    let engines: any EngineSource
    let store: LearnedStore?
    private let modeMemory: (any ModeMemory)?
    var assembler: CandidateAssembler
    let expression: ExpressionEngine
    let loading = LoadingEngine()

    weak var client: (any InputClient)?
    private var lastCJKMode: InputMode
    /// The engine composing right now (a language engine or the `v`
    /// expression engine).
    var active: (any CompositionEngine)? {
        didSet {
            if active == nil {
                forgotten = []
                composedTyped = ""
            }
        }
    }
    var list = CandidateList()
    /// Candidates forgotten during this composition, kept out of the list
    /// though an engine still has them until it reads its words again.
    var forgotten: Set<String> = []
    /// The keys typed for this composition as last shown, which outlives
    /// the engine's state when it commits.
    var composedTyped = ""
    /// Japanese shows the candidate window from the second conversion key.
    var showsConversionWindow = false
    /// Text a function key (F6–F10) turned the composition into.
    var transformed: String?
    var punctuator = ChinesePunctuator()
    var context = ""
    /// The field's text around the caret when its first composition began,
    /// plus what was committed since: its words rank first while the field
    /// has focus (document vocabulary). Kept in memory only.
    var vocabulary = ""
    /// The field's text has been read for `vocabulary` since it gained
    /// focus. Not read on focus, where reading the field can stall it.
    var readsVocabulary = true
    /// The commit ⌃⌫ can take back.
    var undoable: PendingUndo?
    /// The Japanese commit 英数 twice retypes as its romaji, or the romaji
    /// かな twice turns back.
    var retypable: Retypable?
    /// The character just before the caret when Sugu knows it: the last it
    /// committed or let through. Some hosts report the field late, so this
    /// is trusted over reading it; nil once the caret may have moved.
    var lastTyped: Character?
    /// Apple's language models (ADR 0004); nil where unavailable.
    public var assistant: (any LanguageAssistant)?
    /// Model suggestions for a reading, and the translation languages asked.
    var suggestions: (reading: String, languages: [AssistLanguage], result: CompositionSuggestions)?
    var suggestionTask: Task<Void, Never>?
    /// The reading a suggestion request is out for.
    var pendingSuggestion: String?

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
        engines.onEngineReady = { [weak self] mode in self?.engineBecameReady(mode) }
    }

    public var isEmpty: Bool { active?.state.isEmpty ?? true }

    private func applyPreferences() {
        endSuggestions()
        punctuator.width = preferences.punctuationWidth
        loading.holdsZhuyin = preferences.chineseKeyboard == .zhuyin
        list.pageSize = max(1, min(10, preferences.candidatesPerPage))
        if var latin = assembler.latin {
            latin.allowList = Set(preferences.latinAllowList.map { $0.lowercased() })
            assembler.latin = latin
        }
        if !preferences.enabledModes.contains(mode) {
            setMode(preferences.enabledModes.first ?? .english)
        }
        applyChineseScript()
        // Candidates on screen follow a script change at once.
        if active != nil { refresh() }
    }

    private func applyChineseScript() {
        engines.setChineseScript(chineseScript)
        punctuator.script = chineseScript
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
        retypable = nil
        lastTyped = nil
        vocabulary = ""
        readsVocabulary = true
        let bundleID = client.bundleIdentifier
        let rule = preferences.rule(for: bundleID)
        applyChineseScript()
        if let mode = rule.defaultMode {
            setMode(mode, byUser: false)
        } else if preferences.rememberModePerApp, let bundleID, let remembered = modeMemory?.mode(for: bundleID) {
            setMode(remembered, byUser: false)
        }
        if mode != .english { engines.prepare(mode) }
        publish()
    }

    /// Detaches a field that lost focus, committing what is composed.
    public func detach(_ client: any InputClient) {
        guard self.client === client else { return }
        if !isEmpty { commitComposition() }
        endSuggestions()
        self.client = nil
        vocabulary = ""
    }

    // MARK: Modes

    /// Switches to `newMode`. A switch not `byUser` follows the focused
    /// app's rule or remembered mode, and is not itself remembered.
    public func setMode(_ newMode: InputMode, byUser: Bool = true) {
        guard preferences.enabledModes.contains(newMode) || newMode == .english else { return }
        if newMode != mode, !isEmpty { commitComposition() }
        let changed = newMode != mode
        mode = newMode
        if newMode != .english { lastCJKMode = newMode }
        if byUser, preferences.rememberModePerApp, let bundleID = client?.bundleIdentifier {
            modeMemory?.remember(newMode, for: bundleID)
        }
        publish()
        if changed {
            if newMode != .english { engines.prepare(newMode) }
            onModeChange?(newMode, byUser)
        }
    }

    /// The caret may have moved without a key (a click in the field).
    public func caretMayHaveMoved() {
        lastTyped = nil
    }

    /// A Shift tap: switches to English, and a Chinese composition of typed
    /// letters is committed as those letters, which were meant as English.
    /// A composition with a choice made in it is committed as it shows.
    public func shiftTapped() {
        if mode == .chinese, let engine = active, transformed == nil,
           !engine.state.isEmpty, engine.state.segments.allSatisfy({ $0.role == .input }),
           let raw = engine.commitRaw() {
            commitText(raw.text, reading: raw.reading, learn: false)
        }
        toggleEnglish()
    }

    /// English ↔ the last Chinese or Japanese mode.
    public func toggleEnglish(byUser: Bool = true) {
        setMode(mode == .english ? lastCJKMode : .english, byUser: byUser)
    }

    /// Chinese ↔ Japanese, when both are enabled.
    public func switchCJKMode() {
        let cjk = preferences.enabledModes.filter { $0 != .english }
        guard cjk.count > 1 else { setMode(cjk.first ?? .english); return }
        let current = mode == .english ? lastCJKMode : mode
        let next = cjk[(cjk.firstIndex(of: current).map { $0 + 1 } ?? 0) % cjk.count]
        setMode(next)
    }
}
