import Foundation

/// Decodes dictionary text files, which arrive as UTF-8, UTF-16 with a byte
/// order mark (ATOK, Microsoft IME), Shift_JIS, or GB18030 (Sogou).
enum TextDecoding {
    static func string(from data: Data) -> String? {
        let bytes = [UInt8](data.prefix(3))
        if bytes.starts(with: [0xFF, 0xFE]) { return String(data: data.dropFirst(2), encoding: .utf16LittleEndian) }
        if bytes.starts(with: [0xFE, 0xFF]) { return String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return String(data: data.dropFirst(3), encoding: .utf8) }
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        // A prefix may end inside a multibyte UTF-8 character.
        if data.count >= 4, let utf8 = String(data: data.dropLast(3), encoding: .utf8) { return utf8 }
        if let shiftJIS = String(data: data, encoding: .shiftJIS) { return shiftJIS }
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: data, encoding: String.Encoding(rawValue: gb18030))
    }

    static func lines(of data: Data) -> [Substring]? {
        string(from: data)?.split(whereSeparator: \.isNewline)
    }
}
