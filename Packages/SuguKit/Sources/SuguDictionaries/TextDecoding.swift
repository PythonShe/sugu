import Foundation
import SuguCore

/// Decodes dictionary text files, which arrive as UTF-8, UTF-16 with a byte
/// order mark (ATOK, Microsoft IME), Shift_JIS, or GB18030 (Sogou).
enum TextDecoding {
    /// `language` is the language the file's format is written in: its
    /// legacy encoding is tried first. Without one, Shift_JIS is tried
    /// first but not taken when it reads as half-width katakana, as
    /// Chinese GBK text does. A `prefix` may end inside a character, so up
    /// to three bytes are dropped from its end; a whole file that does
    /// loses its last line instead.
    static func string(from data: Data, language: InputMode? = nil, prefix: Bool = false) -> String? {
        let cuts = prefix ? 0...min(3, max(0, data.count - 1)) : 0...0
        func decode(_ body: Data, _ encoding: String.Encoding) -> String? {
            cuts.lazy.compactMap { String(data: body.dropLast($0), encoding: encoding) }.first
        }
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xFF, 0xFE]) { return decode(data.dropFirst(2), .utf16LittleEndian) }
        if bytes.starts(with: [0xFE, 0xFF]) { return decode(data.dropFirst(2), .utf16BigEndian) }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return decode(data.dropFirst(3), .utf8) }
        if let utf8 = decode(data, .utf8) { return utf8 }
        // A file cut short inside a character: its last line is not whole.
        if !prefix, data.count > 3, let utf8 = (1...3).lazy.compactMap({ String(data: data.dropLast($0), encoding: .utf8) }).first {
            return String(utf8[..<(utf8.lastIndex(where: \.isNewline) ?? utf8.startIndex)])
        }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        switch language {
        case .chinese: return decode(data, gb18030) ?? decode(data, .shiftJIS)
        case .japanese: return decode(data, .shiftJIS) ?? decode(data, gb18030)
        default:
            if let shiftJIS = decode(data, .shiftJIS), !shiftJIS.unicodeScalars.contains(where: isHalfWidthKatakana) { return shiftJIS }
            return decode(data, gb18030) ?? decode(data, .shiftJIS)
        }
    }

    static func lines(of data: Data, language: InputMode? = nil) -> [Substring]? {
        string(from: data, language: language)?.split(whereSeparator: \.isNewline)
    }

    private static func isHalfWidthKatakana(_ scalar: Unicode.Scalar) -> Bool {
        (0xFF61...0xFF9F).contains(scalar.value)
    }
}
