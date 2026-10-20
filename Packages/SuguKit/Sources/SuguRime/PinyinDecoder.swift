import Foundation

/// Reads typed keys back as toneless syllables under a schema's spelling
/// rules, so a learned word typed in any scheme can be written into
/// librime's user dictionary in syllables.
public struct PinyinDecoder: Sendable {
    private struct Reading: Sendable {
        var syllable: String
        var isDerived: Bool
    }

    private let readings: [String: [Reading]]
    private let longestSpelling: Int

    /// Spellings of `syllables` under `rules`, as written in a schema.
    init(syllables: some Sequence<String>, rules: [String]) {
        let algebra = SpellingAlgebra(rules: rules)
        var readings: [String: [Reading]] = [:]
        for syllable in syllables {
            for spelling in algebra.spellings(of: syllable) {
                readings[spelling.text, default: []].append(Reading(syllable: syllable, isDerived: spelling.isDerived))
            }
        }
        self.readings = readings
        longestSpelling = readings.keys.map(\.count).max() ?? 0
    }

    /// The decoder for a schema, with its rules read from the shared data
    /// directory; nil when a rule file is missing.
    public init?(schema: RimeSchema, syllables: Set<String>, sharedData: URL) {
        var rules: [String] = []
        for patch in schema.algebraPatches {
            guard let patchRules = SpellingAlgebra.rules(patch: patch, in: sharedData) else { return nil }
            rules += patchRules
        }
        self.init(syllables: syllables, rules: rules)
    }

    /// Syllable sequences that type `keys` as exactly `count` syllables,
    /// those needing the fewest derived spellings first, at most `limit`;
    /// only those, unless `fewestDerivedOnly` is false. An apostrophe is a
    /// boundary no syllable crosses.
    public func syllables(typedAs keys: String, count: Int, limit: Int = 4, fewestDerivedOnly: Bool = true) -> [[String]] {
        let keys = Array(keys)
        guard count > 0, keys.count >= count else { return [] }
        // The `limit` sequences needing the fewest derived spellings to type
        // keys[position...] as `remaining` syllables, cheapest first.
        var memo: [Int: [(cost: Int, syllables: [String])]] = [:]
        func solve(_ position: Int, _ remaining: Int) -> [(cost: Int, syllables: [String])] {
            if position == keys.count { return remaining == 0 ? [(0, [])] : [] }
            if keys[position] == "'" { return solve(position + 1, remaining) }
            if remaining == 0 { return [] }
            let key = position * (count + 1) + remaining
            if let known = memo[key] { return known }
            var found: [(cost: Int, syllables: [String])] = []
            for end in (position + 1)...min(keys.count, position + longestSpelling) {
                guard let options = readings[String(keys[position..<end])] else { continue }
                let rest = solve(end, remaining - 1)
                for option in options {
                    for sequence in rest {
                        let candidate = [option.syllable] + sequence.syllables
                        guard !found.contains(where: { $0.syllables == candidate }) else { continue }
                        found.append((sequence.cost + (option.isDerived ? 1 : 0), candidate))
                    }
                }
            }
            // Stable, so equal costs keep the order they were found in.
            let best = Array(found.enumerated().sorted { ($0.element.cost, $0.offset) < ($1.element.cost, $1.offset) }.map(\.element).prefix(limit))
            memo[key] = best
            return best
        }
        let sequences = solve(0, count)
        let fewest = sequences.first?.cost
        return sequences.filter { !fewestDerivedOnly || $0.cost == fewest }.map(\.syllables)
    }
}
