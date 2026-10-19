/// A string proposed for the current composition.
public struct Candidate: Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        /// Produced by the active engine; `index` is its position in the
        /// engine's own list, used to select it back.
        case engine(index: Int)
        /// A learned or user word that matches the whole reading.
        case learned
        /// Dates, numerals, arithmetic.
        case computed
        /// The typed letters as Latin text.
        case latin
    }

    public var text: String
    /// Secondary text shown next to the candidate (reading hint, comment).
    public var annotation: String?
    public var source: Source

    public init(text: String, annotation: String? = nil, source: Source) {
        self.text = text
        self.annotation = annotation
        self.source = source
    }

    public var engineIndex: Int? {
        if case .engine(let index) = source { return index }
        return nil
    }
}
