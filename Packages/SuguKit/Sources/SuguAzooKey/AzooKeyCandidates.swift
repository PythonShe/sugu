internal import KanaKanjiConverterModuleWithDefaultDictionary
import SuguCore

/// What Sugu reads from the converter's candidates: clauses, names, and
/// readings.
extension KanaKanjiConverterModule.Candidate {
    /// The first clause of this sentence: one the converter proposed, or,
    /// when refinement rewrote that clause, the converter's clause of the
    /// same length as this sentence writes it.
    func firstClause(among clauses: [KanaKanjiConverterModule.Candidate], total: Int) -> KanaKanjiConverterModule.Candidate? {
        let spans = clauses.filter { $0.rubyCount > 0 && $0.rubyCount < total }
        if let proposed = spans.filter({ text.hasPrefix($0.text) }).max(by: { $0.value < $1.value }) {
            return proposed
        }
        guard data.map(\.word).joined() == text else { return nil }
        return spans.compactMap { clause -> KanaKanjiConverterModule.Candidate? in
            var words: [DicdataElement] = []
            var length = 0
            for word in data where length < clause.rubyCount {
                words.append(word)
                length += word.ruby.count
            }
            guard length == clause.rubyCount, let last = words.last else { return nil }
            return KanaKanjiConverterModule.Candidate(
                text: words.map(\.word).joined(), value: clause.value, composingCount: clause.composingCount,
                lastMid: last.mid, data: words
            )
        }.max { $0.value < $1.value }
    }

    /// Word classes of names: places, people, organizations.
    private static let properNounClasses: Set<Int> = Set(
        [CIDData.固有名詞, .人名一般, .人名姓, .人名名, .固有名詞組織, .地名一般].map(\.cid)
    )
    private static let personClasses: Set<Int> = Set([CIDData.人名一般, .人名姓, .人名名].map(\.cid))
    private static let placeClasses: Set<Int> = [CIDData.地名一般.cid]

    /// The kind of name this is when all of it is one.
    var nameKind: SuguCore.Candidate.Name? {
        let classes = Set(data.map(\.lcid))
        guard !classes.isEmpty, classes.isSubset(of: Self.properNounClasses) else { return nil }
        if classes.isSubset(of: Self.personClasses) { return .person }
        if classes.isSubset(of: Self.placeClasses) { return .place }
        return .other
    }

    /// The reading in hiragana, when it differs from the text.
    var readingHint: String? {
        let reading = WidthConversion.hiragana(data.map(\.ruby).joined())
        return reading == text || reading.isEmpty ? nil : reading
    }
}
