/// Caret motions inside a composition.
public enum CaretMotion: Sendable {
    case left, right, start, end
}

/// The result of choosing a candidate.
public enum SelectionResult: Sendable, Equatable {
    /// Part of the input was fixed; the composition continues.
    case continued
    /// The whole composition is done; `text` goes to the document.
    case committed(Commit)
}

/// Text leaving a composition, with what was typed to produce it.
public struct Commit: Sendable, Equatable {
    public var text: String
    public var reading: String
    /// Clause-level pairs (reading → text) when the engine knows them; used
    /// for learning. Empty when only the whole commit is known.
    public var clauses: [Clause]

    public struct Clause: Sendable, Equatable {
        public var reading: String
        public var text: String
        public init(reading: String, text: String) {
            self.reading = reading
            self.text = text
        }
    }

    public init(text: String, reading: String, clauses: [Clause] = []) {
        self.text = text
        self.reading = reading
        self.clauses = clauses
    }
}

/// How an engine composes, which decides how the input session binds keys
/// and treats what it commits.
public struct EngineTraits: Sendable, Equatable {
    public enum Composition: Sendable, Equatable {
        /// Candidates are live while typing and the first is chosen by
        /// default (pinyin, expressions).
        case live
        /// Typing shows predictions and Space converts in a phase of its
        /// own, clause by clause (Japanese).
        case staged
        /// The whole input stays converted as it is typed, and the
        /// candidate window opens on the words at the caret (Zhuyin).
        case sentence
    }

    public var composition: Composition
    /// Commits teach the learned store and ⌃⌫ can take them back into the
    /// engine.
    public var learnsCommits: Bool
    /// Sugu adds its own candidates (learned, computed, Latin) to the
    /// engine's.
    public var takesSuguCandidates: Bool
    /// The composition stands for text already in the document (a selection
    /// being translated): Esc puts it back as it was.
    public var revisesText: Bool

    public init(composition: Composition, learnsCommits: Bool, takesSuguCandidates: Bool, revisesText: Bool = false) {
        self.composition = composition
        self.learnsCommits = learnsCommits
        self.takesSuguCandidates = takesSuguCandidates
        self.revisesText = revisesText
    }
}

/// One language engine driving one composition. Implementations own the raw
/// input and conversion state; Sugu's input session owns key bindings,
/// modes, punctuation, and candidates that do not come from the engine.
@MainActor
public protocol CompositionEngine: AnyObject {
    var traits: EngineTraits { get }
    var state: CompositionState { get }

    /// Characters this engine accepts as input in the current state.
    func accepts(_ character: Character) -> Bool
    func insert(_ text: String)
    func deleteBackward()
    func deleteForward()
    func moveCaret(_ motion: CaretMotion)

    /// Enters the converting phase. Returns false if there is nothing to
    /// convert.
    @discardableResult func convert() -> Bool
    /// Leaves the converting phase, back to plain input.
    func cancelConversion()
    func highlight(_ index: Int)
    func select(_ index: Int) -> SelectionResult
    /// Moves the focus to the neighboring clause (Japanese).
    func moveFocus(forward: Bool)
    /// Grows or shrinks the focused clause by one character (Japanese).
    func resizeFocus(by delta: Int)

    /// Commits what is shown: converted clauses, or the best conversion.
    func commitConverted() -> Commit?
    /// Commits the raw input: letters for Chinese, kana for Japanese.
    func commitRaw() -> Commit?
    func clear()
    /// Starts a composition from a reading, as after undo-after-commit.
    func restore(reading: String)
    /// Committed text left of the caret, to inform ranking.
    func setLeftContext(_ text: String)
    /// Drops input not yet part of the composition's text (a half-typed
    /// Zhuyin syllable); false when there is none.
    func clearPending() -> Bool
    /// Text the composition let go of from its start (a long Zhuyin
    /// sentence), to commit while the rest composes on.
    func takeOverflow() -> Commit?
}

extension CompositionEngine {
    public func clearPending() -> Bool { false }
    public func takeOverflow() -> Commit? { nil }
}
