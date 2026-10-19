import Foundation
import SuguCore

/// Sogou's cell dictionary format (.scel): a pinyin syllable table, then
/// groups of words that share a pinyin sequence. Strings are UTF-16LE.
enum SogouCell {
    private static let magic: [UInt8] = [0x40, 0x15, 0x00, 0x00, 0x44, 0x43, 0x53, 0x01]
    private static let syllableTableOffset = 0x1540
    private static let wordsOffset = 0x2628

    static func read(_ data: Data) throws -> [DictionaryEntry] {
        let bytes = [UInt8](data)
        guard bytes.count > wordsOffset, Array(bytes.prefix(magic.count)) == magic else {
            throw DictionaryImporter.Error.unreadable
        }
        var reader = Reader(bytes: bytes, position: syllableTableOffset + 4)
        var syllables: [Int: String] = [:]
        while reader.position < wordsOffset {
            // The table may be followed by zero padding.
            guard let index = reader.uint16(), let length = reader.uint16(), length > 0, let name = reader.utf16(length) else { break }
            syllables[index] = name
        }

        var entries: [DictionaryEntry] = []
        reader.position = wordsOffset
        while reader.position < bytes.count {
            guard let homophones = reader.uint16(), let codeLength = reader.uint16() else { break }
            var reading = ""
            for _ in 0..<(codeLength / 2) {
                guard let index = reader.uint16() else { return entries }
                reading += syllables[index] ?? ""
            }
            for _ in 0..<homophones {
                guard let wordLength = reader.uint16(), let word = reader.utf16(wordLength),
                      let extraLength = reader.uint16(), reader.skip(extraLength) else { return entries }
                if !reading.isEmpty, !word.isEmpty {
                    entries.append(DictionaryEntry(mode: .chinese, reading: reading, text: word))
                }
            }
        }
        return entries
    }

    private struct Reader {
        let bytes: [UInt8]
        var position: Int

        mutating func uint16() -> Int? {
            guard position + 2 <= bytes.count else { return nil }
            defer { position += 2 }
            return Int(bytes[position]) | Int(bytes[position + 1]) << 8
        }

        mutating func utf16(_ length: Int) -> String? {
            guard length % 2 == 0, position + length <= bytes.count else { return nil }
            defer { position += length }
            let units = stride(from: position, to: position + length, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
            return String(decoding: units, as: UTF16.self)
        }

        mutating func skip(_ length: Int) -> Bool {
            guard position + length <= bytes.count else { return false }
            position += length
            return true
        }
    }
}
