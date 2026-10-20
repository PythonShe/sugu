import Foundation
import SuguCore
import SuguLearning

/// Sugu's own dictionary file: tab-separated, one word per line, with
/// enough detail (kind, pin, use count, dates) to move a store between
/// Macs without losing ranking. Sync files also list deleted words, with
/// kind `deleted user` or `deleted learned` and the deletion date as
/// last used.
public enum SuguDictionaryFile {
    static let header = "# Sugu dictionary"
    static let version = 1
    private static let deletedPrefix = "deleted "

    public struct Contents: Sendable {
        public var words: [LearnedWord] = []
        public var deletions: [WordDeletion] = []
    }

    public static func encode(_ words: [LearnedWord], deletions: [WordDeletion] = []) -> Data {
        let dates = ISO8601DateFormatter()
        var lines = ["\(header) \(version)", "# mode\treading\ttext\tkind\tpinned\tcount\tfirst used\tlast used"]
        for word in words.sorted(by: { ($0.mode.rawValue, $0.reading, $0.text) < ($1.mode.rawValue, $1.reading, $1.text) }) {
            lines.append([
                word.mode.rawValue, sanitize(word.reading), sanitize(word.text),
                name(of: word.kind), word.pinned ? "1" : "0", String(word.count),
                dates.string(from: word.firstUsed), dates.string(from: word.lastUsed),
            ].joined(separator: "\t"))
        }
        for deletion in deletions.sorted(by: { ($0.mode.rawValue, $0.reading, $0.text) < ($1.mode.rawValue, $1.reading, $1.text) }) {
            let date = dates.string(from: deletion.deletedAt)
            lines.append([
                deletion.mode.rawValue, sanitize(deletion.reading), sanitize(deletion.text),
                deletedPrefix + name(of: deletion.kind), "0", "0", date, date,
            ].joined(separator: "\t"))
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    /// Words in the file. Unknown or malformed lines are skipped.
    public static func decode(_ data: Data) -> [LearnedWord] {
        decodeContents(data).words
    }

    /// Words and deletions in the file. A line without every field, as
    /// the last line of a file cut short, is skipped.
    public static func decodeContents(_ data: Data) -> Contents {
        guard let lines = TextDecoding.lines(of: data) else { return Contents() }
        let dates = ISO8601DateFormatter()
        var contents = Contents()
        for line in lines where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 8, let mode = InputMode(rawValue: fields[0]), !fields[1].isEmpty, !fields[2].isEmpty,
                  let count = Int(fields[5]), let firstUsed = dates.date(from: fields[6]), let lastUsed = dates.date(from: fields[7])
            else { continue }
            if fields[3].hasPrefix(deletedPrefix) {
                guard let kind = kind(named: String(fields[3].dropFirst(deletedPrefix.count))) else { continue }
                contents.deletions.append(WordDeletion(mode: mode, reading: fields[1], text: fields[2], kind: kind, deletedAt: lastUsed))
                continue
            }
            guard let kind = kind(named: fields[3]) else { continue }
            contents.words.append(LearnedWord(
                id: 0, mode: mode, reading: fields[1], text: fields[2], kind: kind,
                count: count, pinned: fields[4] == "1", firstUsed: firstUsed, lastUsed: lastUsed
            ))
        }
        return contents
    }

    private static func name(of kind: LearnedWord.Kind) -> String {
        kind == .user ? "user" : "learned"
    }

    private static func kind(named name: String) -> LearnedWord.Kind? {
        switch name {
        case "user": .user
        case "learned": .learned
        default: nil
        }
    }

    private static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
    }
}
