import Foundation

/// A character n-gram model in backoff form (ADR 0005), memory-mapped from
/// the file `CharacterLanguageModelBuilder` writes. Text is compared after
/// NFKC normalization, as a sequence of Unicode scalars.
///
/// File layout, little-endian: a 24-byte header (`SGLM`, version, order,
/// entry count, log probability of an unseen character, reserved), the
/// entries' keys as sorted `UInt64` hashes, then their log probabilities
/// and backoff weights as `Int16` thousandths.
public final class CharacterLanguageModel: Sendable {
    static let magic: UInt32 = 0x4D4C_4753 // "SGLM"
    static let version: UInt32 = 1
    static let headerSize = 24
    /// Stands before the first character of a text with nothing before it.
    static let start: UInt32 = 0x02

    public let order: Int
    private let data: Data
    private let count: Int
    private let unseen: Float

    public init(contentsOf url: URL) throws {
        data = try Data(contentsOf: url, options: .alwaysMapped)
        guard data.count >= Self.headerSize else { throw ModelError.malformed }
        let header = data.withUnsafeBytes { bytes in
            (0..<6).map { bytes.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self) }
        }
        guard header[0] == Self.magic, header[1] == Self.version, (2...8).contains(header[2]) else { throw ModelError.malformed }
        order = Int(header[2])
        count = Int(header[3])
        unseen = Float(bitPattern: header[4])
        guard data.count == Self.headerSize + count * 12 else { throw ModelError.malformed }
    }

    public enum ModelError: Error {
        case malformed
    }

    /// The natural log probability of `text` following `history`; an empty
    /// history is the start of the text.
    public func logProbability(of text: String, after history: String = "") -> Float {
        let scalars = Self.scalars(text)
        guard !scalars.isEmpty else { return 0 }
        var context = Self.scalars(history).suffix(order - 1).map { $0 }
        if context.isEmpty { context = Array(repeating: Self.start, count: order - 1) }
        return data.withUnsafeBytes { bytes in
            var total: Float = 0
            for scalar in scalars {
                total += logProbability(of: scalar, after: context, in: bytes)
                context.append(scalar)
                if context.count > order - 1 { context.removeFirst() }
            }
            return total
        }
    }

    static func scalars(_ text: String) -> [UInt32] {
        text.precomposedStringWithCompatibilityMapping.unicodeScalars.map(\.value)
    }

    private func logProbability(of scalar: UInt32, after context: [UInt32], in bytes: UnsafeRawBufferPointer) -> Float {
        var backoff: Float = 0
        for length in stride(from: context.count, through: 0, by: -1) {
            let history = context[(context.count - length)...]
            if let index = find(Self.hash(history, then: scalar), in: bytes) {
                return backoff + value(at: index, column: 0, in: bytes)
            }
            if length > 0, let index = find(Self.hash(history), in: bytes) {
                backoff += value(at: index, column: 1, in: bytes)
            }
        }
        return backoff + unseen
    }

    private func find(_ key: UInt64, in bytes: UnsafeRawBufferPointer) -> Int? {
        var low = 0, high = count
        while low < high {
            let middle = (low + high) / 2
            let probe = bytes.loadUnaligned(fromByteOffset: Self.headerSize + middle * 8, as: UInt64.self)
            if probe == key { return middle }
            if probe < key { low = middle + 1 } else { high = middle }
        }
        return nil
    }

    /// Column 0 is the log probability, 1 the backoff weight.
    private func value(at index: Int, column: Int, in bytes: UnsafeRawBufferPointer) -> Float {
        let offset = Self.headerSize + count * 8 + column * count * 2 + index * 2
        return Float(bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self)) / 1000
    }

    /// FNV-1a over the scalars of an n-gram.
    static func hash(_ scalars: some Sequence<UInt32>, then last: UInt32? = nil) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        func mix(_ scalar: UInt32) {
            for shift in stride(from: 0, to: 32, by: 8) {
                hash ^= UInt64((scalar >> UInt32(shift)) & 0xFF)
                hash = hash &* 0x0000_0100_0000_01B3
            }
        }
        for scalar in scalars { mix(scalar) }
        if let last { mix(last) }
        return hash
    }
}
