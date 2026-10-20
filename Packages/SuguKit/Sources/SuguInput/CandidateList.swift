import SuguCore

/// The candidates of one composition and the user's place in them: the
/// highlighted row and the page on screen. Only list arithmetic; the
/// session decides what a highlight means for the engine.
struct CandidateList {
    var candidates: [Candidate] = []
    var highlight: Int?
    var page = 0
    var pageSize = 5

    var isEmpty: Bool { candidates.isEmpty }

    var highlighted: Candidate? { highlight.flatMap { candidates[safe: $0] } }

    mutating func clear() {
        candidates = []
        highlight = nil
        page = 0
    }

    /// Highlights `index` (nil for none) and shows its page.
    mutating func setHighlight(_ index: Int?) {
        highlight = index
        page = (index ?? 0) / pageSize
    }

    /// The candidate index of a row on the current page.
    func index(onPage row: Int) -> Int? {
        guard (0..<pageSize).contains(row) else { return nil }
        let index = page * pageSize + row
        return candidates.indices.contains(index) ? index : nil
    }

    /// The index `delta` rows from the highlight, kept within the list.
    /// Without a highlight, moving forward starts at the first row.
    func index(movingHighlightBy delta: Int) -> Int? {
        guard !candidates.isEmpty else { return nil }
        let current = highlight ?? (delta > 0 ? -1 : 0)
        return min(max(0, current + delta), candidates.count - 1)
    }

    /// The page `delta` pages away, kept within the list; nil when that is
    /// the current page.
    func page(turnedBy delta: Int) -> Int? {
        guard !candidates.isEmpty else { return nil }
        let pages = (candidates.count + pageSize - 1) / pageSize
        let target = min(max(0, page + delta), pages - 1)
        return target == page ? nil : target
    }

    /// The current page's rows, and the highlighted row among them.
    var currentPage: (rows: [Candidate], highlight: Int?, hasPrevious: Bool, hasNext: Bool) {
        let start = page * pageSize
        let end = min(candidates.count, start + pageSize)
        guard start < end else { return ([], nil, page > 0, false) }
        let row = highlight.flatMap { (start..<end).contains($0) ? $0 - start : nil }
        return (Array(candidates[start..<end]), row, page > 0, end < candidates.count)
    }
}
