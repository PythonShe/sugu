import Foundation
import SuguCore
import SuguLearning

/// Reads other input methods' dictionaries into entries for Sugu's store.
public enum DictionaryImporter {
    public enum Error: Swift.Error, Equatable {
        case unrecognizedFormat
        case unreadable
        /// More entries than `maximumEntries`.
        case tooLarge
    }

    /// Most entries one file may add. Imported words never expire and are
    /// kept in memory for lookups, so a whole system dictionary is refused.
    public static let maximumEntries = 100_000

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
        case .wordList:
            guard let lines = TextDecoding.lines(of: data) else { throw Error.unreadable }
            entries = lines.compactMap { $0.hasPrefix("#") ? nil : wordListEntry($0) }
        }
        var seen = Set<DictionaryEntry>()
        let unique = entries.filter { seen.insert($0).inserted }
        guard unique.count <= maximumEntries else { throw Error.tooLarge }
        return unique
    }

    private static func lines(_ data: Data, language: InputMode) throws -> [Substring] {
        guard let lines = TextDecoding.lines(of: data, language: language) else { throw Error.unreadable }
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
        try lines(data, language: .japanese).compactMap { line in
            guard !line.hasPrefix("!") else { return nil }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2 else { return nil }
            return entry(reading: fields[0], text: fields[1])
        }
    }

    /// `'ni'hao 你好`
    static func sogouText(_ data: Data) throws -> [DictionaryEntry] {
        try lines(data, language: .chinese).compactMap { line in
            guard line.hasPrefix("'"), let space = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
            let reading = line[..<space].split(separator: "'").joined()
            return entry(reading: reading, text: line[space...])
        }
    }

    /// One line of a word list: a reading and a word, in either order, split
    /// by a tab or a comma (more columns are ignored), or by spaces, where
    /// the reading may be pinyin in syllables (`ni hao 你好`). Quotes around
    /// a field are dropped. Nil when no field reads as a reading.
    static func wordListEntry(_ line: some StringProtocol) -> DictionaryEntry? {
        let separators: [Character] = line.contains("\t") ? ["\t"] : line.contains(",") || line.contains("，") ? [",", "，"] : [" ", "　"]
        let fields = line.split(whereSeparator: { separators.contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
            .filter { !$0.isEmpty }
        guard fields.count >= 2 else { return nil }
        let isReading = fields.map { DictionaryEntry.mode(forReading: $0) != nil }
        if separators.contains(" "), let word = fields.indices.first(where: { !isReading[$0] }),
           fields.indices.allSatisfy({ $0 == word || isReading[$0] }) {
            // Spaces: the one field that is no reading is the word.
            let reading = fields.indices.filter { $0 != word }.map { fields[$0] }.joined()
            return entry(reading: reading, text: fields[word])
        }
        switch (isReading[0], isReading[1]) {
        case (true, false): return entry(reading: fields[0], text: fields[1])
        // Kana for kana (すぐ, スグ); letters for letters is prose.
        case (true, true): return fields[1].allSatisfy(\.isASCII) ? nil : entry(reading: fields[0], text: fields[1])
        case (false, true): return entry(reading: fields[1], text: fields[0])
        case (false, false): return nil
        }
    }

    /// `text<TAB>code<TAB>weight`, after the YAML header when there is one.
    static func rime(_ data: Data) throws -> [DictionaryEntry] {
        let lines = try lines(data, language: .chinese)
        let body = lines.firstIndex(of: "...").map { lines[($0 + 1)...] } ?? lines[...]
        return body.compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2 else { return nil }
            return entry(reading: fields[1].split(separator: " ").joined(), text: fields[0])
        }
    }
}
