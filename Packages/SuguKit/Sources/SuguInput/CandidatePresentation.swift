import SuguCore

/// One page of candidates as the candidate window shows it.
public struct CandidatePresentation: Sendable, Equatable {
    public var candidates: [Candidate]
    /// Highlighted row within this page, nil when nothing is highlighted.
    public var highlightedIndex: Int?
    public var page: Int
    public var hasPreviousPage: Bool
    public var hasNextPage: Bool
    /// Predictions shown while typing, before any conversion.
    public var isPrediction: Bool

    public init(candidates: [Candidate], highlightedIndex: Int?, page: Int = 0, hasPreviousPage: Bool = false, hasNextPage: Bool = false, isPrediction: Bool = false) {
        self.candidates = candidates
        self.highlightedIndex = highlightedIndex
        self.page = page
        self.hasPreviousPage = hasPreviousPage
        self.hasNextPage = hasNextPage
        self.isPrediction = isPrediction
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

    /// Where in the composition, in characters, the candidates belong: the
    /// focused clause, or else the text after the fixed clauses or
    /// librime's confirmed words; the candidate window opens under it.
    public var candidateAnchor: Int {
        let target = segments.firstIndex { $0.role == .focused } ?? segments.firstIndex { $0.role != .converted }
        guard let target else { return 0 }
        return segments[..<target].map(\.text.count).reduce(0, +)
    }
}
