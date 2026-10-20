import Foundation

/// Counts character n-grams in sentences and writes the model
/// `CharacterLanguageModel` reads: interpolated Kneser-Ney with one discount
/// per order, then rare n-grams pruned and the backoff weights renormalized
/// so each context's probabilities still sum to one.
public struct CharacterLanguageModelBuilder {
    public let order: Int
    /// N-grams of at least three characters seen fewer times are dropped.
    public var minimumCount = 2
    private var counts: [[UInt32]: Int] = [:]
    public private(set) var sentences = 0

    public init(order: Int = 5) {
        precondition((2...8).contains(order))
        self.order = order
    }

    public mutating func add(_ sentence: String) {
        let scalars = CharacterLanguageModel.scalars(sentence.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !scalars.isEmpty else { return }
        sentences += 1
        let padded = Array(repeating: CharacterLanguageModel.start, count: order - 1) + scalars
        for end in (order - 1)..<padded.count {
            for length in 1...order {
                counts[Array(padded[(end - length + 1)...end]), default: 0] += 1
            }
        }
    }

    /// The model file; `entries` is how many n-grams and contexts it holds.
    public func build() -> (data: Data, entries: Int) {
        // Kneser-Ney counts: raw for the highest order, otherwise the number
        // of distinct characters seen before the n-gram.
        var adjusted: [[UInt32]: Int] = [:]
        for (gram, count) in counts where gram.count == order { adjusted[gram] = count }
        for gram in counts.keys where gram.count > 1 { adjusted[Array(gram.dropFirst()), default: 0] += 1 }

        var discounts = [Double](repeating: 0.75, count: order + 1)
        for length in 1...order {
            var once = 0, twice = 0
            for (gram, count) in adjusted where gram.count == length {
                if count == 1 { once += 1 } else if count == 2 { twice += 1 }
            }
            if once > 0, twice > 0 { discounts[length] = Double(once) / Double(once + 2 * twice) }
        }
        var totals: [[UInt32]: (sum: Int, types: Int)] = [:]
        for (gram, count) in adjusted {
            let context = Array(gram.dropLast())
            totals[context, default: (0, 0)].sum += count
            totals[context, default: (0, 0)].types += 1
        }
        let vocabulary = Double(adjusted.keys.filter { $0.count == 1 }.count + 1)
        let unseen = log(discounts[1] * Double(totals[[]]!.types) / Double(totals[[]]!.sum) / vocabulary)

        // Interpolated probabilities, by increasing order.
        var probability: [[UInt32]: Double] = [:]
        func interpolated(_ gram: [UInt32]) -> Double {
            if let known = probability[gram] { return known }
            let context = Array(gram.dropLast())
            let lower = gram.count == 1 ? 1 / vocabulary : interpolated(Array(gram.dropFirst()))
            guard let total = totals[context] else { return lower }
            let discount = discounts[gram.count]
            let count = Double(adjusted[gram] ?? 0)
            return max(count - discount, 0) / Double(total.sum) + discount * Double(total.types) / Double(total.sum) * lower
        }
        for length in 1...order {
            for gram in adjusted.keys where gram.count == length { probability[gram] = interpolated(gram) }
        }

        let kept = Set(counts.filter { $0.key.count < 3 || $0.value >= minimumCount }.keys)
        // Each context keeps the mass of its pruned characters for the
        // lower order: backoff = (1 - Σ kept P(w|h)) / (1 - Σ kept P(w|h')).
        var keptMass: [[UInt32]: (here: Double, lower: Double)] = [:]
        var entries: [UInt64: (probability: Double, backoff: Double)] = [:]
        func backedOff(_ gram: [UInt32]) -> Double {
            if kept.contains(gram) { return probability[gram]! }
            guard gram.count > 1 else { return exp(unseen) }
            let context = Array(gram.dropLast())
            return backoffWeight(context) * backedOff(Array(gram.dropFirst()))
        }
        func backoffWeight(_ context: [UInt32]) -> Double {
            guard let mass = keptMass[context] else { return 1 }
            return max(1 - mass.here, 1e-9) / max(1 - mass.lower, 1e-9)
        }
        // Sorted, so sums add in the same order and builds are identical.
        let ordered = kept.sorted { $0.count != $1.count ? $0.count < $1.count : $0.lexicographicallyPrecedes($1) }
        for length in 1...order {
            // Lower orders are final before a higher order needs them.
            for gram in ordered where gram.count == length {
                let context = Array(gram.dropLast())
                let lower = length == 1 ? exp(unseen) : backedOff(Array(gram.dropFirst()))
                keptMass[context, default: (0, 0)].here += probability[gram]!
                keptMass[context, default: (0, 0)].lower += lower
            }
        }
        for gram in kept {
            entries[CharacterLanguageModel.hash(gram)] = (log(probability[gram]!), 0)
        }
        for context in keptMass.keys where !context.isEmpty {
            let key = CharacterLanguageModel.hash(context)
            // Contexts of start markers only are not n-grams themselves.
            entries[key, default: (-99, 0)].backoff = log(backoffWeight(context))
        }

        let keys = entries.keys.sorted()
        var data = Data()
        func append<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        append(CharacterLanguageModel.magic)
        append(CharacterLanguageModel.version)
        append(UInt32(order))
        append(UInt32(keys.count))
        append(Float(unseen).bitPattern)
        append(UInt32(0))
        for key in keys { append(key.littleEndian) }
        func quantized(_ value: Double) -> Int16 { Int16(max(-32_767, min(32_767, (value * 1000).rounded()))) }
        for key in keys { append(quantized(entries[key]!.probability).littleEndian) }
        for key in keys { append(quantized(entries[key]!.backoff).littleEndian) }
        return (data, keys.count)
    }
}
