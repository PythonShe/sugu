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
        /// The Chinese form of a Japanese name (東京 → 东京).
        case chineseForm
        /// From a language model (ADR 0004): a conversion, which is learned
        /// when chosen, or a translation or rewrite, which is not.
        case model(learns: Bool)
    }

    public var text: String
    /// Secondary text shown next to the candidate (reading hint, comment).
    public var annotation: String?
    public var source: Source
    /// What kind of name the candidate is, as the engine tagged it.
    public var name: Name?

    public enum Name: Sendable, Hashable {
        case person, place
        /// An organization's, or a name of no one kind.
        case other
    }

    public init(text: String, annotation: String? = nil, source: Source, name: Name? = nil) {
        self.text = text
        self.annotation = annotation
        self.source = source
        self.name = name
    }

    /// A place, person or organization name.
    public var isProperNoun: Bool { name != nil }

    public var engineIndex: Int? {
        if case .engine(let index) = source { return index }
        return nil
    }
}
