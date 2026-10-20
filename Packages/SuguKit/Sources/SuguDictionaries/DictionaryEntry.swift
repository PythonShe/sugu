import Foundation
import SuguCore

/// One word moving into or out of Sugu: a reading, its text, and the mode
/// it belongs to.
public struct DictionaryEntry: Sendable, Hashable {
    public var mode: InputMode
    public var reading: String
    public var text: String

    public init(mode: InputMode, reading: String, text: String) {
        self.mode = mode
        self.reading = reading
        self.text = text
    }

    /// The mode a reading belongs to: kana is Japanese, pinyin letters are
    /// Chinese. Anything else has no place in Sugu's dictionary.
    public static func mode(forReading reading: String) -> InputMode? {
        let trimmed = reading.filter { $0 != " " && $0 != "'" }
        guard !trimmed.isEmpty else { return nil }
        if trimmed.unicodeScalars.allSatisfy(\.isKana) {
            return .japanese
        }
        if trimmed.allSatisfy({ $0.isASCIILetter }) { return .chinese }
        return nil
    }
}
