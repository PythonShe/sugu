import Foundation
import SuguCore

/// Sugu's single store of learned and user words, over both engines.
///
/// Lookups are served from memory so the keystroke path never touches
/// disk; every change is written through to SQLite. The file is excluded
/// from backups and created with file data protection.
@MainActor
public final class LearnedStore {
    public static let didChangeNotification = Notification.Name("SuguLearnedStoreDidChange")

    /// Longest commit, in characters, learned as one word. Longer commits
    /// are sentences, not vocabulary.
    public static let maximumWordLength = 12

    private let database: SQLiteDatabase
    private let clock: @Sendable () -> Date
    private var words: [Int64: LearnedWord] = [:]
    private var index: [IndexKey: [Int64]] = [:]

    private struct IndexKey: Hashable {
        var mode: InputMode
        var reading: String
    }

    /// Opens or creates the store at `url`.
    public init(url: URL, clock: @escaping @Sendable () -> Date = Date.init) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)

        database = try SQLiteDatabase(url: url)
        try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        self.clock = clock
        try migrate()
        try loadAll()
    }

    private func migrate() throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS words (
            id INTEGER PRIMARY KEY,
            mode TEXT NOT NULL,
            reading TEXT NOT NULL,
            text TEXT NOT NULL,
            kind INTEGER NOT NULL,
            count INTEGER NOT NULL,
            pinned INTEGER NOT NULL DEFAULT 0,
            first_used REAL NOT NULL,
            last_used REAL NOT NULL,
            UNIQUE (mode, reading, text)
        );
        CREATE TABLE IF NOT EXISTS events (
            word_id INTEGER NOT NULL REFERENCES words(id) ON DELETE CASCADE,
            at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS events_at ON events(at);
        """)
    }

    private func loadAll() throws {
        words = [:]
        index = [:]
        try database.query("SELECT id, mode, reading, text, kind, count, pinned, first_used, last_used FROM words") { row in
            guard let mode = InputMode(rawValue: row.string(1)), let kind = LearnedWord.Kind(rawValue: Int(row.int(4))) else { return }
            insertInMemory(LearnedWord(
                id: row.int(0), mode: mode, reading: row.string(2), text: row.string(3), kind: kind,
                count: Int(row.int(5)), pinned: row.int(6) != 0,
                firstUsed: Date(timeIntervalSinceReferenceDate: row.double(7)),
                lastUsed: Date(timeIntervalSinceReferenceDate: row.double(8))
            ))
        }
    }

    // MARK: Reading

    /// Words for exactly this reading, best first.
    public func lookup(_ reading: String, mode: InputMode) -> [LearnedWord] {
        let key = IndexKey(mode: mode, reading: LearnedWord.normalize(reading, mode: mode))
        guard let ids = index[key] else { return [] }
        let now = clock()
        return ids.compactMap { words[$0] }.sorted { $0.score(at: now) > $1.score(at: now) }
    }

    /// The best-known reading of a text, for reconversion.
    public func reading(for text: String, mode: InputMode) -> String? {
        let now = clock()
        return words.values
            .filter { $0.mode == mode && $0.text == text }
            .max { $0.score(at: now) < $1.score(at: now) }?
            .reading
    }

    /// Every word, most recently used first, for the inspector.
    public func allWords(mode: InputMode? = nil) -> [LearnedWord] {
        words.values
            .filter { mode == nil || $0.mode == mode }
            .sorted { $0.lastUsed > $1.lastUsed }
    }

    public var count: Int { words.count }

    // MARK: Learning

    /// Learns from a commit: each converted clause and, when it is short
    /// enough to be a word, the whole commit.
    public func learn(_ commit: Commit, mode: InputMode) {
        var pairs = commit.clauses.filter { $0.text != $0.reading }.map { ($0.reading, $0.text) }
        if commit.text.count <= Self.maximumWordLength, commit.text != commit.reading, !pairs.contains(where: { $0.1 == commit.text }) {
            pairs.append((commit.reading, commit.text))
        }
        let now = clock()
        do {
            try database.transaction {
                for (reading, text) in pairs {
                    try recordUse(reading: reading, text: text, mode: mode, kind: .learned, at: now)
                }
                try database.run("DELETE FROM events WHERE at < ?", [.real(now.addingTimeInterval(-7_200).timeIntervalSinceReferenceDate)])
            }
        } catch {
            try? loadAll()
        }
        notify()
    }

    /// Adds a word the user typed in, or imported.
    @discardableResult
    public func addUserWord(reading: String, text: String, mode: InputMode) -> Bool {
        let reading = LearnedWord.normalize(reading, mode: mode)
        guard !reading.isEmpty, !text.isEmpty else { return false }
        do {
            try database.transaction {
                try recordUse(reading: reading, text: text, mode: mode, kind: .user, at: clock(), logEvent: false)
            }
            notify()
            return true
        } catch {
            return false
        }
    }

    /// Adds many user words in one transaction; returns how many were new.
    public func importUserWords(_ entries: [(reading: String, text: String, mode: InputMode)]) throws -> Int {
        var added = 0
        let now = clock()
        try database.transaction {
            for entry in entries {
                let reading = LearnedWord.normalize(entry.reading, mode: entry.mode)
                guard !reading.isEmpty, !entry.text.isEmpty else { continue }
                if index[IndexKey(mode: entry.mode, reading: reading)]?.contains(where: { words[$0]?.text == entry.text }) != true {
                    added += 1
                }
                try recordUse(reading: reading, text: entry.text, mode: entry.mode, kind: .user, at: now, logEvent: false)
            }
        }
        notify()
        return added
    }

    private func recordUse(reading rawReading: String, text: String, mode: InputMode, kind: LearnedWord.Kind, at now: Date, logEvent: Bool = true) throws {
        let reading = LearnedWord.normalize(rawReading, mode: mode)
        guard !reading.isEmpty, !text.isEmpty else { return }
        let key = IndexKey(mode: mode, reading: reading)
        if let id = index[key]?.first(where: { words[$0]?.text == text }), var word = words[id] {
            word.count += kind == .learned ? 1 : 0
            word.lastUsed = now
            if kind == .user { word.kind = .user }
            try database.run("UPDATE words SET count = ?, last_used = ?, kind = ? WHERE id = ?",
                             [.integer(Int64(word.count)), .real(now.timeIntervalSinceReferenceDate), .integer(Int64(word.kind.rawValue)), .integer(id)])
            words[id] = word
            if logEvent { try database.run("INSERT INTO events (word_id, at) VALUES (?, ?)", [.integer(id), .real(now.timeIntervalSinceReferenceDate)]) }
            return
        }
        let id = try database.run(
            "INSERT INTO words (mode, reading, text, kind, count, pinned, first_used, last_used) VALUES (?, ?, ?, ?, ?, 0, ?, ?)",
            [.text(mode.rawValue), .text(reading), .text(text), .integer(Int64(kind.rawValue)), .integer(kind == .learned ? 1 : 0),
             .real(now.timeIntervalSinceReferenceDate), .real(now.timeIntervalSinceReferenceDate)]
        )
        insertInMemory(LearnedWord(id: id, mode: mode, reading: reading, text: text, kind: kind, count: kind == .learned ? 1 : 0, pinned: false, firstUsed: now, lastUsed: now))
        if logEvent { try database.run("INSERT INTO events (word_id, at) VALUES (?, ?)", [.integer(id), .real(now.timeIntervalSinceReferenceDate)]) }
    }

    // MARK: Control

    public func setPinned(_ pinned: Bool, id: Int64) {
        guard var word = words[id] else { return }
        word.pinned = pinned
        _ = try? database.run("UPDATE words SET pinned = ? WHERE id = ?", [.integer(pinned ? 1 : 0), .integer(id)])
        words[id] = word
        notify()
    }

    public func delete(ids: [Int64]) {
        guard !ids.isEmpty else { return }
        try? database.transaction {
            for id in ids {
                try database.run("DELETE FROM words WHERE id = ?", [.integer(id)])
                removeFromMemory(id)
            }
        }
        notify()
    }

    /// Undoes learning from the last `interval`: uses recorded in that time
    /// are taken back, and learned words left without uses are deleted.
    /// Pinned and user words keep their entries.
    public func forget(since interval: TimeInterval = 3_600) {
        let cutoff = clock().addingTimeInterval(-interval).timeIntervalSinceReferenceDate
        var recent: [Int64: Int] = [:]
        try? database.query("SELECT word_id, COUNT(*) FROM events WHERE at >= ? GROUP BY word_id", [.real(cutoff)]) { row in
            recent[row.int(0)] = Int(row.int(1))
        }
        try? database.transaction {
            for (id, uses) in recent {
                guard var word = words[id] else { continue }
                word.count = max(0, word.count - uses)
                if word.count == 0, word.kind == .learned, !word.pinned {
                    try database.run("DELETE FROM words WHERE id = ?", [.integer(id)])
                    removeFromMemory(id)
                } else {
                    try database.run("UPDATE words SET count = ? WHERE id = ?", [.integer(Int64(word.count)), .integer(id)])
                    words[id] = word
                }
            }
            try database.run("DELETE FROM events WHERE at >= ?", [.real(cutoff)])
        }
        notify()
    }

    /// Deletes learned words unused for `days`. Pinned and user words stay.
    @discardableResult
    public func expire(olderThan days: Int) -> Int {
        guard days > 0 else { return 0 }
        let cutoff = clock().addingTimeInterval(-Double(days) * 86_400)
        let stale = words.values.filter { $0.kind == .learned && !$0.pinned && $0.lastUsed < cutoff }.map(\.id)
        delete(ids: stale)
        return stale.count
    }

    public func deleteAll(mode: InputMode? = nil) {
        delete(ids: words.values.filter { mode == nil || $0.mode == mode }.map(\.id))
    }

    // MARK: Memory index

    private func insertInMemory(_ word: LearnedWord) {
        words[word.id] = word
        index[IndexKey(mode: word.mode, reading: word.reading), default: []].append(word.id)
    }

    private func removeFromMemory(_ id: Int64) {
        guard let word = words.removeValue(forKey: id) else { return }
        let key = IndexKey(mode: word.mode, reading: word.reading)
        index[key]?.removeAll { $0 == id }
        if index[key]?.isEmpty == true { index[key] = nil }
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
