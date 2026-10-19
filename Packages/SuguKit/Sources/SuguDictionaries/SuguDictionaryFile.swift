import Foundation
import SuguCore
import SuguLearning

/// Sugu's own dictionary file: tab-separated, one word per line, with
/// enough detail (kind, pin, use count, dates) to move a store between
/// Macs without losing ranking.
public enum SuguDictionaryFile {
    static let header = "# Sugu dictionary"
    static let version = 1

    public static func encode(_ words: [LearnedWord]) -> Data {
        let dates = ISO8601DateFormatter()
        var lines = ["\(header) \(version)", "# mode\treading\ttext\tkind\tpinned\tcount\tfirst used\tlast used"]
        for word in words.sorted(by: { ($0.mode.rawValue, $0.reading, $0.text) < ($1.mode.rawValue, $1.reading, $1.text) }) {
            lines.append([
                word.mode.rawValue, sanitize(word.reading), sanitize(word.text),
                word.kind == .user ? "user" : "learned", word.pinned ? "1" : "0", String(word.count),
                dates.string(from: word.firstUsed), dates.string(from: word.lastUsed),
            ].joined(separator: "\t"))
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    /// Words in the file. Unknown or malformed lines are skipped.
    public static func decode(_ data: Data) -> [LearnedWord] {
        guard let lines = TextDecoding.lines(of: data) else { return [] }
        let dates = ISO8601DateFormatter()
        return lines.compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3, let mode = InputMode(rawValue: fields[0]), !fields[1].isEmpty, !fields[2].isEmpty else { return nil }
            let now = Date()
            func field(_ index: Int) -> String? { fields.indices.contains(index) ? fields[index] : nil }
            return LearnedWord(
                id: 0, mode: mode, reading: fields[1], text: fields[2],
                kind: field(3) == "learned" ? .learned : .user,
                count: field(5).flatMap(Int.init) ?? 0,
                pinned: field(4) == "1",
                firstUsed: field(6).flatMap(dates.date(from:)) ?? now,
                lastUsed: field(7).flatMap(dates.date(from:)) ?? now
            )
        }
    }

    private static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ")
    }
}
