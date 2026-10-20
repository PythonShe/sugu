/// A run of the marked (pre-edit) text with the role it plays.
public struct CompositionSegment: Sendable, Equatable {
    public enum Role: Sendable, Equatable {
        /// Raw input not yet converted (pinyin letters, kana).
        case input
        /// Converted text that is not the focus of the candidate list.
        case converted
        /// The clause the candidate list currently applies to.
        case focused
    }

    public var text: String
    public var role: Role

    public init(_ text: String, role: Role) {
        self.text = text
        self.role = role
    }
}

/// What an engine shows for the composition in progress.
public struct CompositionState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// Typing; candidates, if any, are predictions for the whole input.
        case composing
        /// A conversion is active; the candidate list belongs to the focused
        /// clause and one candidate is highlighted.
        case converting
    }

    public var segments: [CompositionSegment]
    /// Caret position in the joined segment text, in characters.
    public var caret: Int
    public var candidates: [Candidate]
    /// Highlighted index into `candidates`, nil when none is highlighted.
    public var highlightedIndex: Int?
    public var phase: Phase
    /// The full reading as typed (pinyin letters, or kana), used for learning
    /// and to restore the composition after undo.
    public var reading: String
    /// The keys as typed (romaji for Japanese), for F9/F10. Empty when it
    /// equals `reading`.
    public var typed: String

    public init(segments: [CompositionSegment] = [], caret: Int = 0, candidates: [Candidate] = [], highlightedIndex: Int? = nil, phase: Phase = .composing, reading: String = "", typed: String = "") {
        self.segments = segments
        self.caret = caret
        self.candidates = candidates
        self.highlightedIndex = highlightedIndex
        self.phase = phase
        self.reading = reading
        self.typed = typed
    }

    /// Keys as typed, falling back to the reading.
    public var typedText: String { typed.isEmpty ? reading : typed }

    public static let empty = CompositionState()

    public var isEmpty: Bool { segments.allSatisfy { $0.text.isEmpty } }
    public var markedText: String { segments.map(\.text).joined() }
}
