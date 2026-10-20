import Foundation


/// Character n-grams of what the user typed (D-079), counted in memory
/// from the learned store, which persists them. Each n-gram is two to
/// `order` characters: a context and the character after it.
@MainActor
public final class PersonalNGrams {
    public let order: Int
    private var counts: [UInt64: Int] = [:]
    /// How often each context was followed by any character.
    private var totals: [UInt64: Int] = [:]
    /// Changes with every count, so scores kept across keystrokes can tell
    /// when they are out of date.
    public private(set) var version = 0

    public init(order: Int = 5) {
        precondition((2...8).contains(order))
        self.order = order
    }

    public var isEmpty: Bool { counts.isEmpty }

    /// How often the user typed an n-gram.
    public func count(of gram: String) -> Int {
        counts[CharacterLanguageModel.hash(CharacterLanguageModel.scalars(gram))] ?? 0
    }

    /// The n-grams of `text` after `context`, as `add` takes them: every run
    /// of two to `order` scalars that ends in `text`, after the same
    /// normalization the model reads text with, so text that reads the
    /// same gives the same n-grams.
    public static func grams(of text: String, after context: String, order: Int = 5) -> [String] {
        let typed = CharacterLanguageModel.scalars(text)
        let scalars = CharacterLanguageModel.scalars(context).suffix(order - 1) + typed
        let start = scalars.count - typed.count
        var grams: [String] = []
        for end in start..<scalars.count {
            for length in 2...order where end - length + 1 >= 0 {
                var gram = ""
                gram.unicodeScalars.append(contentsOf: scalars[(end - length + 1)...end].compactMap(Unicode.Scalar.init))
                grams.append(gram)
            }
        }
        return grams
    }

    /// Adds `delta` uses of an n-gram; a count that falls to zero is removed.
    public func add(_ gram: String, count delta: Int) {
        let scalars = CharacterLanguageModel.scalars(gram)
        guard (2...order).contains(scalars.count), delta != 0 else { return }
        let key = CharacterLanguageModel.hash(scalars)
        let context = CharacterLanguageModel.hash(scalars.dropLast())
        let applied = max(delta, -(counts[key] ?? 0))
        guard applied != 0 else { return }
        counts[key, default: 0] += applied
        if counts[key] == 0 { counts[key] = nil }
        totals[context, default: 0] += applied
        if totals[context] == 0 { totals[context] = nil }
        version += 1
    }

    public func removeAll() {
        counts = [:]
        totals = [:]
        version += 1
    }

    /// Most of a character's probability the user's counts may take.
    static let maximumWeight: Float = 0.5
    /// Uses of a context at which its counts take half of `maximumWeight`.
    static let halfWeightUses: Float = 1

    /// The user's probability of `scalar` after `context`, from the longest
    /// context they typed, and the weight it carries: more for a context
    /// typed more often. Nil when the user never typed any of it.
    func estimate(of scalar: UInt32, after context: [UInt32]) -> (probability: Float, weight: Float)? {
        for length in stride(from: min(context.count, order - 1), through: 1, by: -1) {
            let history = context[(context.count - length)...]
            guard let total = totals[CharacterLanguageModel.hash(history)] else { continue }
            let count = counts[CharacterLanguageModel.hash(history, then: scalar)] ?? 0
            let uses = Float(total)
            let weight = Self.maximumWeight * uses / (uses + Self.halfWeightUses)
            return (Float(count) / uses, weight)
        }
        return nil
    }
}

/// The bundled character model with the user's n-grams interpolated into
/// it, character by character, where the user typed the context before.
@MainActor
public final class BlendedLanguageModel {
    public let base: CharacterLanguageModel
    /// Nil while personal n-grams are turned off.
    public var personal: PersonalNGrams?

    public init(base: CharacterLanguageModel, personal: PersonalNGrams? = nil) {
        self.base = base
        self.personal = personal
    }

    public var order: Int { base.order }

    /// Changes whenever scores may: with the user's counts, or with whether
    /// they are used.
    public var version: Int { personal.map { $0.version + 1 } ?? 0 }

    /// The natural log probability of `text` following `history`; an empty
    /// history is the start of the text.
    public func logProbability(of text: String, after history: String = "") -> Float {
        guard let personal, !personal.isEmpty else { return base.logProbability(of: text, after: history) }
        let scalars = CharacterLanguageModel.scalars(text)
        var context = Array(CharacterLanguageModel.scalars(history).suffix(order - 1))
        // The user's n-grams never hold the start marker, so contexts with
        // it fall to the shorter ones without.
        if context.isEmpty { context = Array(repeating: CharacterLanguageModel.start, count: order - 1) }
        var total: Float = 0
        for scalar in scalars {
            let logProbability = base.logProbability(of: scalar, after: context)
            if let estimate = personal.estimate(of: scalar, after: context) {
                let mixed = (1 - estimate.weight) * exp(logProbability) + estimate.weight * estimate.probability
                total += log(max(mixed, .leastNormalMagnitude))
            } else {
                total += logProbability
            }
            context.append(scalar)
            if context.count > order - 1 { context.removeFirst() }
        }
        return total
    }
}
