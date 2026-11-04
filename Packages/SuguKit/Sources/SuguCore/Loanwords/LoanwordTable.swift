import Foundation

/// A compiled dictionary from foreign spellings to katakana, memory-mapped
/// so it costs little until read. Keys are sorted and found by binary
/// search.
///
/// Layout, little-endian: magic and version; key count; key offsets
/// (count + 1); word offsets (count + 1); one flag byte per key, padded to
/// four bytes; key bytes; word bytes, a key's words separated by newlines.
public final class LoanwordTable: Sendable {
    public struct Entry: Sendable, Equatable {
        public var key: String
        /// Best first.
        public var words: [String]
        /// Whether the key's romaji also spells a native Japanese word
        /// (`take`, 竹), so its ordinary conversions should stay ahead.
        public var alsoJapanese: Bool

        public init(key: String, words: [String], alsoJapanese: Bool = false) {
            self.key = key
            self.words = words
            self.alsoJapanese = alsoJapanese
        }
    }

    public enum LoadError: Error {
        case invalidFormat
    }

    private static let magic: UInt32 = 0x314C_4753 // "SGL1"

    private let data: Data
    public let count: Int
    private let keyBytesStart: Int
    private let wordBytesStart: Int

    public convenience init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public init(data: Data) throws {
        guard data.count >= 8 else { throw LoadError.invalidFormat }
        let (magic, count): (UInt32, Int) = data.withUnsafeBytes {
            ($0.loadUnaligned(fromByteOffset: 0, as: UInt32.self), Int($0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)))
        }
        let tables = 8 + (count + 1) * 8 + (count + 3) / 4 * 4
        guard magic == Self.magic, data.count >= tables else { throw LoadError.invalidFormat }
        let (keyBytes, wordBytes): (Int, Int) = data.withUnsafeBytes {
            (Int($0.loadUnaligned(fromByteOffset: 8 + count * 4, as: UInt32.self)),
             Int($0.loadUnaligned(fromByteOffset: 8 + (count + 1) * 4 + count * 4, as: UInt32.self)))
        }
        guard data.count == tables + keyBytes + wordBytes else { throw LoadError.invalidFormat }
        self.data = data
        self.count = count
        keyBytesStart = tables
        wordBytesStart = tables + keyBytes
    }

    /// The entry for a key from `LoanwordSpelling.key`.
    public func entry(for key: String) -> Entry? {
        var key = key
        return key.withUTF8 { needle in
            data.withUnsafeBytes { bytes -> Entry? in
                var low = 0
                var high = count - 1
                while low <= high {
                    let middle = (low + high) / 2
                    let start = Int(bytes.loadUnaligned(fromByteOffset: 8 + middle * 4, as: UInt32.self))
                    let end = Int(bytes.loadUnaligned(fromByteOffset: 8 + (middle + 1) * 4, as: UInt32.self))
                    let candidate = UnsafeRawBufferPointer(rebasing: bytes[(keyBytesStart + start)..<(keyBytesStart + end)])
                    let order = Self.compare(needle, candidate)
                    if order == 0 { return Self.read(bytes, at: middle, count: count, wordBytesStart: wordBytesStart, key: String(decoding: needle, as: UTF8.self)) }
                    if order < 0 { high = middle - 1 } else { low = middle + 1 }
                }
                return nil
            }
        }
    }

    private static func compare(_ left: UnsafeBufferPointer<UInt8>, _ right: UnsafeRawBufferPointer) -> Int {
        for index in 0..<min(left.count, right.count) where left[index] != right[index] {
            return Int(left[index]) - Int(right[index])
        }
        return left.count - right.count
    }

    private static func read(_ bytes: UnsafeRawBufferPointer, at index: Int, count: Int, wordBytesStart: Int, key: String) -> Entry {
        let table = 8 + (count + 1) * 4
        let start = Int(bytes.loadUnaligned(fromByteOffset: table + index * 4, as: UInt32.self))
        let end = Int(bytes.loadUnaligned(fromByteOffset: table + (index + 1) * 4, as: UInt32.self))
        let flags = bytes[table + (count + 1) * 4 + index]
        let words = bytes[(wordBytesStart + start)..<(wordBytesStart + end)]
            .split(separator: UInt8(ascii: "\n"))
            .map { String(decoding: $0, as: UTF8.self) }
        return Entry(key: key, words: words, alsoJapanese: flags & 1 != 0)
    }

    /// Compiles entries into the format above.
    public static func encode(_ entries: [Entry]) -> Data {
        let sorted = entries.sorted { Array($0.key.utf8).lexicographicallyPrecedes(Array($1.key.utf8)) }
        var keyBytes = Data()
        var wordBytes = Data()
        var keyOffsets: [UInt32] = [0]
        var wordOffsets: [UInt32] = [0]
        var flags = Data()
        for entry in sorted {
            keyBytes.append(contentsOf: entry.key.utf8)
            keyOffsets.append(UInt32(keyBytes.count))
            wordBytes.append(contentsOf: entry.words.joined(separator: "\n").utf8)
            wordOffsets.append(UInt32(wordBytes.count))
            flags.append(entry.alsoJapanese ? 1 : 0)
        }
        flags.append(contentsOf: repeatElement(0, count: (4 - flags.count % 4) % 4))
        var result = Data()
        func append(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { result.append(contentsOf: $0) } }
        append(magic)
        append(UInt32(sorted.count))
        keyOffsets.forEach(append)
        wordOffsets.forEach(append)
        result.append(flags)
        result.append(keyBytes)
        result.append(wordBytes)
        return result
    }
}
