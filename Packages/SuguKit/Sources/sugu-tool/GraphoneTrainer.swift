import Foundation
import SuguCore

/// Trains `KatakanaGuesser`'s model from (spelling, katakana) pairs: EM
/// aligns letters to kana, then absolute discounting estimates a trigram
/// model over the aligned graphones (Bisani and Ney's joint-sequence models).
struct GraphoneTrainer {
    struct Pair: Sendable {
        var letters: [UInt8]
        var units: [String]
        /// Kana chunk ids: `chunks[j * (maximumKana + 1) + b]` is the `b`
        /// units from `j`.
        var chunks: [UInt32]
    }

    static let maximumLetters = KatakanaGuesser.maximumChunk
    static let maximumKana = 2
    /// The search needs a letter to make progress, and a long silent chunk
    /// would swallow letters that should be read.
    static let maximumSilentLetters = 2
    static let iterations = 7
    static let emSample = 60_000
    static let discount = 0.85
    /// Pairs that align worst, per letter, are likelier wrong than hard.
    static let noisyShare = 0.05

    private var kanaIDs: [String: UInt32] = ["": 0]
    private(set) var kanaChunks: [String] = [""]

    /// Splits kana into units, a small kana staying with the one before.
    static func units(_ kana: String) -> [String] {
        var result: [String] = []
        for character in kana {
            if "ァィゥェォャュョヮ".contains(character), !result.isEmpty {
                result[result.count - 1].append(character)
            } else {
                result.append(String(character))
            }
        }
        return result
    }

    mutating func pair(key: String, kana: String) -> Pair {
        let units = Self.units(kana)
        var chunks = [UInt32](repeating: UInt32.max, count: (units.count + 1) * (Self.maximumKana + 1))
        for start in 0...units.count {
            chunks[start * (Self.maximumKana + 1)] = 0
            for length in 1...Self.maximumKana where start + length <= units.count {
                let text = units[start..<(start + length)].joined()
                let id = kanaIDs[text] ?? {
                    let id = UInt32(kanaChunks.count)
                    kanaIDs[text] = id
                    kanaChunks.append(text)
                    return id
                }()
                chunks[start * (Self.maximumKana + 1) + length] = id
            }
        }
        return Pair(letters: Array(key.utf8), units: units, chunks: chunks)
    }

    private static func graphone(_ letters: [UInt8], _ start: Int, _ length: Int, _ kana: UInt32) -> UInt64 {
        var index: UInt64 = 0
        for position in start..<(start + length) { index = index * 27 + UInt64(letters[position] - 0x60) }
        return index << 32 | UInt64(kana)
    }

    /// Counts every chunk pair near the diagonal, shorter ones heavier, so
    /// EM starts from something tractable.
    private func initialTable(_ pairs: [Pair]) -> [UInt64: Double] {
        var table: [UInt64: Double] = [:]
        let stride = Self.maximumKana + 1
        for pair in pairs {
            let n = pair.letters.count, m = pair.units.count
            for i in 0..<n {
                let diagonal = Double(i) * Double(m) / Double(n)
                for j in 0...m where abs(Double(j) - diagonal) <= max(3, Double(m) * 0.35) {
                    for a in 1...min(Self.maximumLetters, n - i) {
                        for b in 0...min(Self.maximumKana, m - j) {
                            if b == 0, a > Self.maximumSilentLetters { continue }
                            let key = Self.graphone(pair.letters, i, a, pair.chunks[j * stride + b])
                            table[key, default: 0] += 1.0 / Double((a + b) * (a + b))
                        }
                    }
                }
            }
        }
        let total = table.values.reduce(0, +)
        return table.mapValues { $0 / total }
    }

    /// Expected graphone counts of one pair.
    private static func expectation(_ pair: Pair, _ table: [UInt64: Double], into counts: inout [UInt64: Double]) -> Bool {
        let n = pair.letters.count, m = pair.units.count
        let width = m + 1
        let stride = maximumKana + 1
        var forward = [Double](repeating: 0, count: (n + 1) * width)
        forward[0] = 1
        for i in 0..<n {
            for j in 0...m {
                let f = forward[i * width + j]
                guard f != 0 else { continue }
                for a in 1...min(maximumLetters, n - i) {
                    for b in 0...min(maximumKana, m - j) {
                        if b == 0, a > maximumSilentLetters { continue }
                        if let p = table[graphone(pair.letters, i, a, pair.chunks[j * stride + b])] {
                            forward[(i + a) * width + j + b] += f * p
                        }
                    }
                }
            }
        }
        let total = forward[n * width + m]
        guard total > 0 else { return false }
        var backward = [Double](repeating: 0, count: (n + 1) * width)
        backward[n * width + m] = 1
        for i in Swift.stride(from: n - 1, through: 0, by: -1) {
            for j in Swift.stride(from: m, through: 0, by: -1) {
                var sum = 0.0
                for a in 1...min(maximumLetters, n - i) {
                    for b in 0...min(maximumKana, m - j) {
                        if b == 0, a > maximumSilentLetters { continue }
                        let after = backward[(i + a) * width + j + b]
                        guard after != 0 else { continue }
                        let key = graphone(pair.letters, i, a, pair.chunks[j * stride + b])
                        guard let p = table[key] else { continue }
                        let value = p * after
                        sum += value
                        let f = forward[i * width + j]
                        if f != 0 { counts[key, default: 0] += f * value / total }
                    }
                }
                backward[i * width + j] = sum
            }
        }
        return true
    }

    /// EM over `pairs`, in fixed batches so the result does not depend on
    /// thread timing.
    func train(_ pairs: [Pair]) async -> [UInt64: Double] {
        var table = initialTable(pairs)
        print("graphone candidates: \(table.count)")
        let batches = 48
        for iteration in 0..<Self.iterations {
            let current = table
            let results = await withTaskGroup(of: (Int, [UInt64: Double], Int).self) { group in
                for batch in 0..<batches {
                    group.addTask {
                        var counts: [UInt64: Double] = [:]
                        var missed = 0
                        for index in Swift.stride(from: batch, to: pairs.count, by: batches) {
                            if !Self.expectation(pairs[index], current, into: &counts) { missed += 1 }
                        }
                        return (batch, counts, missed)
                    }
                }
                var results: [(Int, [UInt64: Double], Int)] = []
                for await result in group { results.append(result) }
                return results.sorted { $0.0 < $1.0 }
            }
            var counts: [UInt64: Double] = [:]
            var missed = 0
            for (_, batch, batchMissed) in results {
                counts.merge(batch, uniquingKeysWith: +)
                missed += batchMissed
            }
            let total = counts.values.reduce(0, +)
            // Rare one-off chunks go, which ties the alignment to fewer of them.
            var next = counts.filter { $0.value > 0.5 && $0.value / total > 1e-7 }
            let kept = next.values.reduce(0, +)
            next = next.mapValues { $0 / kept }
            table = next
            print("EM \(iteration + 1)/\(Self.iterations): \(table.count) graphones, \(missed) pairs unaligned")
        }
        return table
    }

    /// The best alignment of a pair and its log probability per letter.
    func align(_ pair: Pair, logTable: [UInt64: Double]) -> (graphones: [UInt64], score: Double)? {
        let n = pair.letters.count, m = pair.units.count
        let width = m + 1
        let stride = Self.maximumKana + 1
        var best = [Double](repeating: -.infinity, count: (n + 1) * width)
        var from = [Int32](repeating: -1, count: (n + 1) * width)
        var used = [UInt64](repeating: 0, count: (n + 1) * width)
        best[0] = 0
        for i in 0..<n {
            for j in 0...m {
                let score = best[i * width + j]
                guard score > -.infinity else { continue }
                for a in 1...min(Self.maximumLetters, n - i) {
                    for b in 0...min(Self.maximumKana, m - j) {
                        if b == 0, a > Self.maximumSilentLetters { continue }
                        let key = Self.graphone(pair.letters, i, a, pair.chunks[j * stride + b])
                        guard let p = logTable[key] else { continue }
                        let target = (i + a) * width + j + b
                        if score + p > best[target] {
                            best[target] = score + p
                            from[target] = Int32(i * width + j)
                            used[target] = key
                        }
                    }
                }
            }
        }
        let end = n * width + m
        guard best[end] > -.infinity else { return nil }
        var path: [UInt64] = []
        var position = end
        while position != 0 {
            path.append(used[position])
            position = Int(from[position])
        }
        return (path.reversed(), best[end] / Double(n))
    }

    /// The kept alignments and the score below which a pair counts as noise.
    func alignments(_ pairs: [Pair], logTable: [UInt64: Double]) async -> (sequences: [[UInt64]], noiseFloor: Double) {
        let batches = 48
        let results = await withTaskGroup(of: (Int, [[UInt64]], [Double]).self) { group in
            for batch in 0..<batches {
                group.addTask {
                    var sequences: [[UInt64]] = []
                    var scores: [Double] = []
                    for index in Swift.stride(from: batch, to: pairs.count, by: batches) {
                        if let aligned = align(pairs[index], logTable: logTable) {
                            sequences.append(aligned.graphones)
                            scores.append(aligned.score)
                        }
                    }
                    return (batch, sequences, scores)
                }
            }
            var results: [(Int, [[UInt64]], [Double])] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }
        }
        let scores = results.flatMap(\.2)
        let sorted = scores.sorted()
        let floor = sorted[Int(Double(sorted.count) * Self.noisyShare)]
        var kept: [[UInt64]] = []
        for (_, sequences, batchScores) in results {
            for (sequence, score) in zip(sequences, batchScores) where score >= floor { kept.append(sequence) }
        }
        print("aligned \(scores.count) of \(pairs.count) pairs, kept \(kept.count)")
        return (kept, floor)
    }

    /// Estimates the trigram model. Trigrams seen fewer than `minimumTrigram`
    /// times are left to the bigrams, which is most of the model's size.
    func model(from sequences: [[UInt64]], minimumTrigram: Int) -> KatakanaGuesser.Model {
        var alphabet = Set<UInt64>()
        for sequence in sequences { alphabet.formUnion(sequence) }
        let ordered = alphabet.sorted()
        precondition(ordered.count + 2 <= Int(UInt16.max), "too many graphones for 16-bit ids")
        var ids: [UInt64: UInt16] = [:]
        for (index, graphone) in ordered.enumerated() { ids[graphone] = UInt16(index + 2) }

        let (start, end) = (UInt64(0), UInt64(1))
        var unigrams: [UInt64: Int] = [:]
        var bigrams: [UInt64: Int] = [:]
        var trigrams: [UInt64: Int] = [:]
        for sequence in sequences {
            var previous = start, last = start
            for raw in sequence + [UInt64.max] {
                let graphone = raw == .max ? end : UInt64(ids[raw]!)
                unigrams[graphone, default: 0] += 1
                bigrams[last << 16 | graphone, default: 0] += 1
                trigrams[previous << 32 | last << 16 | graphone, default: 0] += 1
                previous = last
                last = graphone
            }
        }
        let d = Self.discount
        let unigramTotal = unigrams.values.reduce(0, +)
        let unigramBackoff = Float(d * Double(unigrams.count) / Double(unigramTotal))

        var bigramTotals: [UInt64: (total: Int, types: Int)] = [:]
        for (key, count) in bigrams {
            let history = key >> 16
            let old = bigramTotals[history] ?? (0, 0)
            bigramTotals[history] = (old.total + count, old.types + 1)
        }
        // A history's total counts its pruned trigrams too, and their mass
        // goes to the backoff: otherwise the kept trigrams are inflated.
        var trigramTotals: [UInt64: (total: Int, types: Int)] = [:]
        var prunedMass: [UInt64: Int] = [:]
        for (key, count) in trigrams {
            let history = key >> 16
            if count >= minimumTrigram {
                let old = trigramTotals[history] ?? (0, 0)
                trigramTotals[history] = (old.total + count, old.types + 1)
            } else {
                prunedMass[history, default: 0] += count
            }
        }
        for (history, mass) in prunedMass where trigramTotals[history] != nil {
            trigramTotals[history]!.total += mass
        }

        func text(_ raw: UInt64) -> (letters: String, kana: String) {
            var index = Int(raw >> 32)
            var letters: [UInt8] = []
            while index > 0 {
                letters.append(UInt8(index % 27) + 0x60)
                index /= 27
            }
            return (String(decoding: letters.reversed(), as: UTF8.self), kanaChunks[Int(raw & 0xFFFF_FFFF)])
        }
        var graphones = [
            KatakanaGuesser.Model.Graphone(letters: "", kana: "", unigram: 0, backoff: Float(bigramTotals[start].map { d * Double($0.types) / Double($0.total) } ?? 0)),
            KatakanaGuesser.Model.Graphone(letters: "", kana: "", unigram: Float(max(Double(unigrams[end] ?? 0) - d, 0.05) / Double(unigramTotal)), backoff: 0),
        ]
        for raw in ordered {
            let id = UInt64(ids[raw]!)
            let (letters, kana) = text(raw)
            let backoff = bigramTotals[id].map { d * Double($0.types) / Double($0.total) } ?? 0
            graphones.append(.init(letters: letters, kana: kana, unigram: Float(max(Double(unigrams[id] ?? 0) - d, 0.05) / Double(unigramTotal)), backoff: Float(backoff)))
        }
        // Sorted so the file is the same however the counts were hashed.
        let bigramEntries = bigrams.keys.sorted().map { key -> (last: UInt16, graphone: UInt16, value: Float) in
            let total = bigramTotals[key >> 16]!.total
            return (UInt16(key >> 16), UInt16(key & 0xFFFF), Float(max(Double(bigrams[key]!) - d, 0.05) / Double(total)))
        }
        let trigramEntries = trigrams.keys.filter { trigrams[$0]! >= minimumTrigram }.sorted().map { key -> (previous: UInt16, last: UInt16, graphone: UInt16, value: Float) in
            let total = trigramTotals[key >> 16]!.total
            return (UInt16(key >> 32), UInt16((key >> 16) & 0xFFFF), UInt16(key & 0xFFFF), Float(max(Double(trigrams[key]!) - d, 0.05) / Double(total)))
        }
        let backoffEntries = trigramTotals.keys.sorted().map { history -> (previous: UInt16, last: UInt16, value: Float) in
            let totals = trigramTotals[history]!
            return (UInt16(history >> 16), UInt16(history & 0xFFFF), Float((d * Double(totals.types) + Double(prunedMass[history] ?? 0)) / Double(totals.total)))
        }
        return KatakanaGuesser.Model(
            graphones: graphones, unigramBackoff: unigramBackoff,
            bigrams: bigramEntries, trigrams: trigramEntries, secondOrderBackoffs: backoffEntries
        )
    }
}
