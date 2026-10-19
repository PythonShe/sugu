import Foundation
import SuguCore
import SuguLearning

/// Reads other input methods' dictionaries into entries for Sugu's store.
public enum DictionaryImporter {
    public enum Error: Swift.Error, Equatable {
        case unrecognizedFormat
        case unreadable
    }

    public static func read(_ url: URL, format: DictionaryFormat? = nil) throws -> [DictionaryEntry] {
        guard let format = format ?? DictionaryFormat.detect(url) else { throw Error.unrecognizedFormat }
        let data = try Data(contentsOf: url)
        let entries: [DictionaryEntry]
        switch format {
        case .sugu:
            entries = SuguDictionaryFile.decode(data).map { DictionaryEntry(mode: $0.mode, reading: $0.reading, text: $0.text) }
        case .textReplacements:
            entries = try textReplacements(data)
        case .googleJapaneseInput, .atok:
            entries = try readingFirst(data)
        case .sogouCell:
            entries = try SogouCell.read(data)
        case .sogouText:
            entries = try sogouText(data)
        case .rime:
            entries = try rime(data)
        }
        var seen = Set<DictionaryEntry>()
        return entries.filter { seen.insert($0).inserted }
    }

    private static func lines(_ data: Data) throws -> [Substring] {
        guard let lines = TextDecoding.lines(of: data) else { throw Error.unreadable }
        return lines
    }

    private static func entry(reading: some StringProtocol, text: some StringProtocol) -> DictionaryEntry? {
        let reading = reading.trimmingCharacters(in: .whitespaces)
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let mode = DictionaryEntry.mode(forReading: reading) else { return nil }
        return DictionaryEntry(mode: mode, reading: mode == .japanese ? WidthConversion.hiragana(reading) : reading.lowercased(), text: text)
    }

    /// An array of `{shortcut, phrase}` dictionaries.
    static func textReplacements(_ data: Data) throws -> [DictionaryEntry] {
        guard let items = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else { throw Error.unreadable }
        return items.compactMap { item in
            guard let shortcut = item["shortcut"] as? String, let phrase = item["phrase"] as? String else { return nil }
            return entry(reading: shortcut, text: phrase)
        }
    }

    /// Google Japanese Input, Microsoft IME and ATOK: `reading<TAB>word<TAB>…`,
    /// with `!` comment lines.
    static func readingFirst(_ data: Data) throws -> [DictionaryEntry] {
        try lines(data).compactMap { line in
            guard !line.hasPrefix("!") else { return nil }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2 else { return nil }
            return entry(reading: fields[0], text: fields[1])
        }
    }

    /// `'ni'hao 你好`
    static func sogouText(_ data: Data) throws -> [DictionaryEntry] {
        try lines(data).compactMap { line in
            guard line.hasPrefix("'"), let space = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
            let reading = line[..<space].split(separator: "'").joined()
            return entry(reading: reading, text: line[space...])
        }
    }

    /// `text<TAB>code<TAB>weight`, after the YAML header when there is one.
    static func rime(_ data: Data) throws -> [DictionaryEntry] {
        let lines = try lines(data)
        let body = lines.firstIndex(of: "...").map { lines[($0 + 1)...] } ?? lines[...]
        return body.compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2 else { return nil }
            return entry(reading: fields[1].split(separator: " ").joined(), text: fields[0])
        }
    }
}
