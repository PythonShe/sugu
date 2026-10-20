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
    /// those needing the fewest derived spellings first, at most `limit`.
    public func syllables(typedAs keys: String, count: Int, limit: Int = 4) -> [[String]] {
        let keys = Array(keys)
        guard count > 0, keys.count >= count else { return [] }
        // best[position][remaining]: fewest derived spellings to type
        // keys[position...] as `remaining` syllables, and those sequences.
        var memo: [Int: (cost: Int, sequences: [[String]])] = [:]
        func solve(_ position: Int, _ remaining: Int) -> (cost: Int, sequences: [[String]]) {
            if position == keys.count { return remaining == 0 ? (0, [[]]) : (.max, []) }
            if remaining == 0 { return (.max, []) }
            let key = position * (count + 1) + remaining
            if let known = memo[key] { return known }
            var best: (cost: Int, sequences: [[String]]) = (.max, [])
            for end in (position + 1)...min(keys.count, position + longestSpelling) {
                guard let options = readings[String(keys[position..<end])] else { continue }
                let rest = solve(end, remaining - 1)
                guard rest.cost != .max else { continue }
                for option in options {
                    let cost = rest.cost + (option.isDerived ? 1 : 0)
                    guard cost <= best.cost else { continue }
                    if cost < best.cost { best = (cost, []) }
                    for sequence in rest.sequences where best.sequences.count < limit {
                        let candidate = [option.syllable] + sequence
                        if !best.sequences.contains(candidate) { best.sequences.append(candidate) }
                    }
                }
            }
            memo[key] = best
            return best
        }
        return solve(0, count).sequences
    }
}
