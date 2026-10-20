import SuguCore

/// One page of candidates as the candidate window shows it.
public struct CandidatePresentation: Sendable, Equatable {
    public var candidates: [Candidate]
    /// Highlighted row within this page, nil when nothing is highlighted.
    public var highlightedIndex: Int?
    public var page: Int
    public var hasPreviousPage: Bool
    public var hasNextPage: Bool
    /// Suggestions shown while typing, before any conversion.
    public var isSuggestion: Bool

    public init(candidates: [Candidate], highlightedIndex: Int?, page: Int = 0, hasPreviousPage: Bool = false, hasNextPage: Bool = false, isSuggestion: Bool = false) {
        self.candidates = candidates
        self.highlightedIndex = highlightedIndex
        self.page = page
        self.hasPreviousPage = hasPreviousPage
        self.hasNextPage = hasNextPage
        self.isSuggestion = isSuggestion
    }

    /// Selection labels for the rows of this page: 1–9, then 0.
    public var labels: [String] {
        candidates.indices.map { $0 == 9 ? "0" : String($0 + 1) }
    }
}

/// Everything the shell renders for the current state.
public struct SessionDisplay: Sendable, Equatable {
    public var mode: InputMode
    public var segments: [CompositionSegment]
    public var caret: Int
    public var candidates: CandidatePresentation?

    public static func idle(_ mode: InputMode) -> SessionDisplay {
        SessionDisplay(mode: mode, segments: [], caret: 0, candidates: nil)
    }
}
