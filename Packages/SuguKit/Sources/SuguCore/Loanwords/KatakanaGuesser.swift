import Foundation

/// Guesses the katakana for a foreign spelling no dictionary holds, whatever
/// its language: a trigram model over graphones, aligned pairs of letters
/// and kana such as (`ph`, `フ`), searched with a beam. The tables are
/// memory-mapped, so it costs little until used.
///
/// Layout, little-endian: `Header`; unigram weights and first-order backoffs
/// (Float, one per graphone); kana text offset and length per graphone;
/// graphone range per letter chunk; kana bytes, padded to eight; then for
/// bigrams, trigrams and second-order backoffs, an open-addressed table of
/// UInt64 keys followed by Float values, padded to eight.
public final class KatakanaGuesser: Sendable {
    public struct Guess: Sendable, Equatable {
        public var text: String
        /// Log probability, for comparing guesses of one spelling.
        public var score: Float
    }

    public enum LoadError: Error {
        case invalidFormat
    }

    /// Longest run of letters a graphone covers.
    public static let maximumChunk = 3
    /// Longer input is not a word; searching it would only cost time.
    public static let maximumLength = 32
    static let magic: UInt32 = 0x314B_4753 // "SGK1"
    static let chunkSlots = 27 * 27 * 27
    /// Reserved graphones: the start and end of a word.
    static let start: UInt16 = 0
    static let end: UInt16 = 1
    private static let floor: Float = 1.0 / 500_000
    public static let defaultBeam = 10

    struct Header {
        var magic: UInt32
        var graphones: UInt32
        var bigramCapacity: UInt32
        var trigramCapacity: UInt32
        var backoffCapacity: UInt32
        var textBytes: UInt32
        var unigramBackoff: Float
        var reserved: UInt32
    }

    private let data: Data
    private let header: Header
    private let unigrams: Int
    private let backoffs: Int
    private let texts: Int
    private let chunks: Int
    private let textBytes: Int
    private let bigramKeys: Int
    private let bigramValues: Int
    private let trigramKeys: Int
    private let trigramValues: Int
    private let backoffKeys: Int
    private let backoffValues: Int

    public convenience init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public init(data: Data) throws {
        guard data.count >= MemoryLayout<Header>.size else { throw LoadError.invalidFormat }
        header = data.withUnsafeBytes { $0.loadUnaligned(as: Header.self) }
        guard header.magic == Self.magic else { throw LoadError.invalidFormat }
        let graphones = Int(header.graphones)
        var offset = MemoryLayout<Header>.size
        func advance(_ bytes: Int) -> Int {
            defer { offset += bytes }
            return offset
        }
        func alignToEight() { offset += (8 - offset % 8) % 8 }
        unigrams = advance(graphones * 4)
        backoffs = advance(graphones * 4)
        texts = advance(graphones * 8)
        chunks = advance(Self.chunkSlots * 8)
        textBytes = advance(Int(header.textBytes))
        alignToEight()
        bigramKeys = advance(Int(header.bigramCapacity) * 8)
        bigramValues = advance(Int(header.bigramCapacity) * 4)
        alignToEight()
        trigramKeys = advance(Int(header.trigramCapacity) * 8)
        trigramValues = advance(Int(header.trigramCapacity) * 4)
        alignToEight()
        backoffKeys = advance(Int(header.backoffCapacity) * 8)
        backoffValues = advance(Int(header.backoffCapacity) * 4)
        alignToEight()
        guard data.count == offset else { throw LoadError.invalidFormat }
        self.data = data
    }

    private struct Hypothesis {
        var score: Float
        var previous: UInt16
        var last: UInt16
        var back: Int32
    }

    /// The likeliest katakana for a key from `LoanwordSpelling.key`, best
    /// first; empty when it holds anything but letters or is too long.
    public func guesses(for key: String, limit: Int = 5, beam: Int = KatakanaGuesser.defaultBeam) -> [Guess] {
        let letters = Array(key.utf8)
        guard !letters.isEmpty, letters.count <= Self.maximumLength,
              letters.allSatisfy({ (0x61...0x7A).contains($0) }) else { return [] }
        return data.withUnsafeBytes { bytes in
            let table = Tables(bytes: bytes, owner: self)
            var bins = Array(repeating: [Hypothesis](), count: letters.count + 1)
            bins[0] = [Hypothesis(score: 0, previous: Self.start, last: Self.start, back: -1)]
            var arena: [(graphone: UInt16, previous: Int32)] = []
            arena.reserveCapacity(letters.count * beam * 8)
            for end in 1...letters.count {
                var reached: [Hypothesis] = []
                reached.reserveCapacity(beam * 8)
                var chunk = 0
                var scale = 1
                for length in 1...min(Self.maximumChunk, end) {
                    chunk += Int(letters[end - length] - 0x60) * scale
                    scale *= 27
                    let range = table.graphones(forChunk: chunk)
                    guard !range.isEmpty else { continue }
                    for hypothesis in bins[end - length] {
                        let backoff = table.backoff(hypothesis.previous, hypothesis.last)
                        for raw in range {
                            let graphone = UInt16(raw)
                            arena.append((graphone, hypothesis.back))
                            reached.append(Hypothesis(
                                score: hypothesis.score + table.logProbability(hypothesis.previous, hypothesis.last, graphone, backoff: backoff),
                                previous: hypothesis.last,
                                last: graphone,
                                back: Int32(arena.count - 1)
                            ))
                        }
                    }
                }
                if reached.count > beam {
                    reached.sort { $0.score > $1.score }
                    reached.removeLast(reached.count - beam)
                }
                bins[end] = reached
            }
            var best: [String: Float] = [:]
            var path: [UInt16] = []
            for hypothesis in bins[letters.count] {
                let backoff = table.backoff(hypothesis.previous, hypothesis.last)
                let score = hypothesis.score + table.logProbability(hypothesis.previous, hypothesis.last, Self.end, backoff: backoff)
                path.removeAll(keepingCapacity: true)
                var back = hypothesis.back
                while back >= 0 {
                    path.append(arena[Int(back)].graphone)
                    back = arena[Int(back)].previous
                }
                var text = ""
                for graphone in path.reversed() { text += table.text(graphone) }
                guard !text.isEmpty else { continue }
                // One text reached by several alignments is that much likelier.
                if let old = best[text] {
                    let high = max(old, score), low = min(old, score)
                    best[text] = high + log1p(exp(low - high))
                } else {
                    best[text] = score
                }
            }
            return best.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(limit)
                .map { Guess(text: $0.key, score: $0.value) }
        }
    }

    /// Typed access to the mapped tables for the length of one search.
    private struct Tables {
        let bytes: UnsafeRawBufferPointer
        let owner: KatakanaGuesser

        func graphones(forChunk chunk: Int) -> Range<Int> {
            let start = Int(bytes.loadUnaligned(fromByteOffset: owner.chunks + chunk * 8, as: UInt32.self))
            let count = Int(bytes.loadUnaligned(fromByteOffset: owner.chunks + chunk * 8 + 4, as: UInt32.self))
            return start..<(start + count)
        }

        func text(_ graphone: UInt16) -> String {
            let offset = owner.texts + Int(graphone) * 8
            let start = owner.textBytes + Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            let length = Int(bytes.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))
            return String(decoding: bytes[start..<(start + length)], as: UTF8.self)
        }

        func lookup(_ key: UInt64, keys: Int, values: Int, capacity: UInt32) -> Float {
            guard capacity > 0 else { return 0 }
            let mask = Int(capacity) - 1
            var slot = KatakanaGuesser.slot(for: key) & mask
            while true {
                let found = bytes.loadUnaligned(fromByteOffset: keys + slot * 8, as: UInt64.self)
                if found == key { return bytes.loadUnaligned(fromByteOffset: values + slot * 4, as: Float.self) }
                if found == 0 { return 0 }
                slot = (slot + 1) & mask
            }
        }

        func backoff(_ previous: UInt16, _ last: UInt16) -> Float {
            lookup(KatakanaGuesser.backoffKey(previous, last), keys: owner.backoffKeys, values: owner.backoffValues, capacity: owner.header.backoffCapacity)
        }

        func logProbability(_ previous: UInt16, _ last: UInt16, _ graphone: UInt16, backoff: Float) -> Float {
            let unigram = bytes.loadUnaligned(fromByteOffset: owner.unigrams + Int(graphone) * 4, as: Float.self)
            var probability = unigram + owner.header.unigramBackoff * KatakanaGuesser.floor
            let lastBackoff = bytes.loadUnaligned(fromByteOffset: owner.backoffs + Int(last) * 4, as: Float.self)
            if lastBackoff > 0 {
                probability = lookup(KatakanaGuesser.bigramKey(last, graphone), keys: owner.bigramKeys, values: owner.bigramValues, capacity: owner.header.bigramCapacity)
                    + lastBackoff * probability
            }
            if backoff > 0 {
                probability = lookup(KatakanaGuesser.trigramKey(previous, last, graphone), keys: owner.trigramKeys, values: owner.trigramValues, capacity: owner.header.trigramCapacity)
                    + backoff * probability
            }
            return log(probability)
        }
    }

    // MARK: Table keys, shared with the trainer

    static func bigramKey(_ last: UInt16, _ graphone: UInt16) -> UInt64 {
        UInt64(last) << 16 | UInt64(graphone)
    }

    static func trigramKey(_ previous: UInt16, _ last: UInt16, _ graphone: UInt16) -> UInt64 {
        UInt64(previous) << 32 | UInt64(last) << 16 | UInt64(graphone)
    }

    /// Offset by one so that (start, start) is not the empty slot.
    static func backoffKey(_ previous: UInt16, _ last: UInt16) -> UInt64 {
        (UInt64(previous) << 16 | UInt64(last)) + 1
    }

    static func slot(for key: UInt64) -> Int {
        let mixed = key &* 0x9E37_79B9_7F4A_7C15
        return Int(truncatingIfNeeded: (mixed ^ (mixed >> 29)) & 0x7FFF_FFFF)
    }

    /// The compiled model. `chunk` is the letters' index in the chunk table.
    public struct Model {
        public struct Graphone {
            public var letters: String
            public var kana: String
            public var unigram: Float
            public var backoff: Float

            public init(letters: String, kana: String, unigram: Float, backoff: Float) {
                self.letters = letters
                self.kana = kana
                self.unigram = unigram
                self.backoff = backoff
            }
        }

        /// Sorted by letters; the first two are the start and end of a word.
        public var graphones: [Graphone]
        public var unigramBackoff: Float
        public var bigrams: [(last: UInt16, graphone: UInt16, value: Float)]
        public var trigrams: [(previous: UInt16, last: UInt16, graphone: UInt16, value: Float)]
        public var secondOrderBackoffs: [(previous: UInt16, last: UInt16, value: Float)]

        public init(graphones: [Graphone], unigramBackoff: Float,
                    bigrams: [(last: UInt16, graphone: UInt16, value: Float)],
                    trigrams: [(previous: UInt16, last: UInt16, graphone: UInt16, value: Float)],
                    secondOrderBackoffs: [(previous: UInt16, last: UInt16, value: Float)]) {
            self.graphones = graphones
            self.unigramBackoff = unigramBackoff
            self.bigrams = bigrams
            self.trigrams = trigrams
            self.secondOrderBackoffs = secondOrderBackoffs
        }
    }

    public static func chunkIndex(_ letters: String) -> Int {
        var index = 0
        var scale = 1
        for byte in letters.utf8.reversed() {
            index += Int(byte - 0x60) * scale
            scale *= 27
        }
        return index
    }

    public static func encode(_ model: Model) -> Data {
        func openTable(_ entries: [(UInt64, Float)]) -> (keys: [UInt64], values: [Float]) {
            var capacity = 2
            while capacity * 7 < entries.count * 10 { capacity *= 2 }
            var keys = [UInt64](repeating: 0, count: capacity)
            var values = [Float](repeating: 0, count: capacity)
            for (key, value) in entries {
                var slot = Self.slot(for: key) & (capacity - 1)
                while keys[slot] != 0 { slot = (slot + 1) & (capacity - 1) }
                keys[slot] = key
                values[slot] = value
            }
            return (keys, values)
        }
        let bigrams = openTable(model.bigrams.map { (bigramKey($0.last, $0.graphone), $0.value) })
        let trigrams = openTable(model.trigrams.map { (trigramKey($0.previous, $0.last, $0.graphone), $0.value) })
        let backoffs = openTable(model.secondOrderBackoffs.map { (backoffKey($0.previous, $0.last), $0.value) })

        var text = Data()
        var textRanges: [UInt32] = []
        var chunkRanges = [UInt32](repeating: 0, count: chunkSlots * 2)
        for (index, graphone) in model.graphones.enumerated() {
            let bytes = Data(graphone.kana.utf8)
            textRanges += [UInt32(text.count), UInt32(bytes.count)]
            text.append(bytes)
            guard index >= 2 else { continue }
            let chunk = chunkIndex(graphone.letters)
            if chunkRanges[chunk * 2 + 1] == 0 { chunkRanges[chunk * 2] = UInt32(index) }
            chunkRanges[chunk * 2 + 1] += 1
        }

        var result = Data()
        func append<T>(_ values: [T]) { values.withUnsafeBytes { result.append(contentsOf: $0) } }
        func alignToEight() { result.append(contentsOf: repeatElement(0, count: (8 - result.count % 8) % 8)) }
        var header = Header(
            magic: magic, graphones: UInt32(model.graphones.count),
            bigramCapacity: UInt32(bigrams.keys.count), trigramCapacity: UInt32(trigrams.keys.count),
            backoffCapacity: UInt32(backoffs.keys.count), textBytes: UInt32(text.count),
            unigramBackoff: model.unigramBackoff, reserved: 0
        )
        withUnsafeBytes(of: &header) { result.append(contentsOf: $0) }
        append(model.graphones.map(\.unigram))
        append(model.graphones.map(\.backoff))
        append(textRanges)
        append(chunkRanges)
        result.append(text)
        alignToEight()
        append(bigrams.keys)
        append(bigrams.values)
        alignToEight()
        append(trigrams.keys)
        append(trigrams.values)
        alignToEight()
        append(backoffs.keys)
        append(backoffs.values)
        alignToEight()
        return result
    }
}
