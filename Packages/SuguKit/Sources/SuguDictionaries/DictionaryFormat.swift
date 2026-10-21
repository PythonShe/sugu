import Foundation
import SuguCore

/// Dictionary files Sugu reads.
public enum DictionaryFormat: String, Sendable, CaseIterable {
    /// Sugu's own export (tab-separated, with a header line).
    case sugu
    /// macOS Text Replacements dragged out of System Settings (.plist).
    case textReplacements
    /// Google Japanese Input export: reading, word, part of speech, comment.
    case googleJapaneseInput
    /// ATOK text export: a header line, then reading, word, part of speech.
    case atok
    /// Sogou cell dictionary (.scel).
    case sogouCell
    /// Sogou text export: `'ni'hao 你好` per line.
    case sogouText
    /// RIME dictionary (.dict.yaml) or exported user dictionary: text, code.
    case rime
    /// A list of the user's own: a reading and a word per line, in either
    /// order, separated by a tab, a comma or spaces (.txt, .csv).
    case wordList

    /// Guesses the format from the file name and its first bytes.
    public static func detect(_ url: URL) -> DictionaryFormat? {
        let name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".scel") { return .sogouCell }
        if name.hasSuffix(".plist") { return .textReplacements }
        if name.hasSuffix(".dict.yaml") { return .rime }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let text = TextDecoding.string(from: data.prefix(4_096), prefix: data.count > 4_096) else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let first = lines.first(where: { !$0.isEmpty }) else { return nil }
        if first.hasPrefix(SuguDictionaryFile.header) { return .sugu }
        if first.hasPrefix("!!ATOK_TANGO_TEXT_HEADER") { return .atok }
        if first.hasPrefix("!Microsoft IME") || first.hasPrefix("!Google") { return .googleJapaneseInput }
        let body = lines.filter { !$0.hasPrefix("#") && !$0.hasPrefix("!") && !$0.isEmpty }
        guard let sample = body.first else { return nil }
        if sample.hasPrefix("'") { return .sogouText }
        let fields = sample.split(separator: "\t", omittingEmptySubsequences: false)
        if fields.count >= 2 {
            // RIME puts the text first; IME exports put the reading first.
            if DictionaryEntry.mode(forReading: String(fields[0])) == .japanese { return .googleJapaneseInput }
            if DictionaryEntry.mode(forReading: String(fields[1])) != nil { return .rime }
        }
        if DictionaryImporter.wordListEntry(sample) != nil { return .wordList }
        return nil
    }
}
