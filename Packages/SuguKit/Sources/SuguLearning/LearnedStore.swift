import Foundation
import os
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
    /// How long a deletion is remembered for sync.
    public static let deletionRetention: TimeInterval = 365 * 86_400

    private let database: SQLiteDatabase
    private let clock: @Sendable () -> Date
    private let syllabary: PinyinSyllabary?
    private var words: [Int64: LearnedWord] = [:]
    private var index: [IndexKey: [Int64]] = [:]
    private var deletions: [WordKey: WordDeletion] = [:]

    private struct IndexKey: Hashable {
        var mode: InputMode
        var reading: String
    }

    private struct WordKey: Hashable {
        var mode: InputMode
        var reading: String
        var text: String
    }

    /// Opens or creates the store at `url`. `syllabary` lets a reading typed
    /// with an apostrophe find words stored without one.
    public init(url: URL, syllabary: PinyinSyllabary? = nil, clock: @escaping @Sendable () -> Date = Date.init) throws {
        let fm = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)

        do {
            database = try Self.open(url)
        } catch let error as SQLiteDatabase.Error where error.isCorruption {
            // A damaged store would end learning for good; it is kept
            // beside a fresh one rather than deleted.
            Log.learning.error("Learned store damaged, set aside: \(error.description, privacy: .public)")
            try Self.setAside(url, at: clock())
            database = try Self.open(url)
        }
        try? fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        self.clock = clock
        self.syllabary = syllabary
        try migrate()
        try loadAll()
    }

    private static func open(_ url: URL) throws -> SQLiteDatabase {
        let database = try SQLiteDatabase(url: url)
        try database.checkIntegrity()
        return database
    }

    /// Renames the store and its journal files to `<name>.damaged-<date>`.
    private static func setAside(_ url: URL, at date: Date) throws {
        let stamp = ISO8601DateFormatter.string(from: date, timeZone: .gmt, formatOptions: [.withFullDate, .withTime])
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            try FileManager.default.moveItem(at: file, to: URL(fileURLWithPath: url.path + ".damaged-\(stamp)" + suffix))
        }
    }

    /// The schema, one step per version: a store at version n runs the
    /// steps after its nth, in one transaction, and records the count as
    /// its version. Steps only add, so a store a newer Sugu wrote still
    /// reads here.
    private static let schema = [
        """
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
        CREATE TABLE IF NOT EXISTS deletions (
            mode TEXT NOT NULL,
            reading TEXT NOT NULL,
            text TEXT NOT NULL,
            kind INTEGER NOT NULL,
            deleted_at REAL NOT NULL,
            PRIMARY KEY (mode, reading, text)
        );
        """,
    ]

    private func migrate() throws {
        var version = 0
        try database.query("PRAGMA user_version") { version = Int($0.int(0)) }
        if version > Self.schema.count {
            Log.learning.notice("Learned store from a newer Sugu (schema \(version, privacy: .public)), used as it is")
        } else if version < Self.schema.count {
            try database.transaction {
                for step in Self.schema[version...] { try database.execute(step) }
                try database.execute("PRAGMA user_version = \(Self.schema.count)")
            }
        }
        _ = try database.run("DELETE FROM deletions WHERE deleted_at < ?",
                             [.real(clock().addingTimeInterval(-Self.deletionRetention).timeIntervalSinceReferenceDate)])
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
        deletions = [:]
        try database.query("SELECT mode, reading, text, kind, deleted_at FROM deletions") { row in
            guard let mode = InputMode(rawValue: row.string(0)), let kind = LearnedWord.Kind(rawValue: Int(row.int(3))) else { return }
            let deletion = WordDeletion(mode: mode, reading: row.string(1), text: row.string(2), kind: kind,
                                        deletedAt: Date(timeIntervalSinceReferenceDate: row.double(4)))
            deletions[WordKey(mode: mode, reading: deletion.reading, text: deletion.text)] = deletion
        }
    }

    // MARK: Reading

    /// Words for this reading, best first. A reading typed with an
    /// apostrophe also finds, after those, words stored without it.
    public func lookup(_ reading: String, mode: InputMode) -> [LearnedWord] {
        let normalized = LearnedWord.normalize(reading, mode: mode)
        let now = clock()
        func ranked(_ ids: [Int64]) -> [LearnedWord] {
            ids.compactMap { words[$0] }.sorted { $0.score(at: now) > $1.score(at: now) }
        }
        let exact = ranked(index[IndexKey(mode: mode, reading: normalized)] ?? [])
        guard mode == .chinese, normalized.contains("'"), let syllabary else { return exact }
        return exact + ranked(index[IndexKey(mode: mode, reading: normalized.filter { $0 != "'" })] ?? [])
            .filter { Self.splits(normalized, as: $0.text.count, in: syllabary) }
    }

    /// Whether a word of `length` characters stored without the apostrophes
    /// of `reading` was typed with the same split: its letters split into a
    /// syllable per character one way only, and that way breaks where the
    /// apostrophes do. 西安 under xian is found for xi'an, not 先 (one
    /// syllable) or 先去 under xianqu for xi'anqu (xian qu), nor 方案
    /// under fangan for fan'gan, which could be either split.
    static func splits(_ reading: String, as length: Int, in syllabary: PinyinSyllabary) -> Bool {
        var breaks = Set<Int>()
        var letters = ""
        for character in reading {
            if character == "'" { breaks.insert(letters.count) } else { letters.append(character) }
        }
        let splits = syllabary.splits(of: letters, count: length)
        return splits.count == 1 && breaks.isSubset(of: splits[0])
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

    /// Words the user deleted, for sync.
    public func allDeletions() -> [WordDeletion] {
        Array(deletions.values)
    }

    // MARK: Learning

    /// Learns from a commit: each converted clause and, when it is short
    /// enough to be a word, the whole commit.
    public func learn(_ commit: Commit, mode: InputMode) {
        let now = clock()
        do {
            try database.transaction {
                for (reading, text) in Self.pairs(learnedFrom: commit) {
                    try recordUse(reading: reading, text: text, mode: mode, kind: .learned, at: now)
                }
                try database.run("DELETE FROM events WHERE at < ?", [.real(now.addingTimeInterval(-7_200).timeIntervalSinceReferenceDate)])
            }
        } catch {
            Log.learning.error("Learning not saved: \(String(describing: error), privacy: .public)")
            try? loadAll()
        }
        notify()
    }

    /// Takes back what `learn` recorded for a commit the user undid: one use
    /// of each word, and the word itself when that was its only use.
    public func unlearn(_ commit: Commit, mode: InputMode) {
        do {
            try database.transaction {
                for (rawReading, text) in Self.pairs(learnedFrom: commit) {
                    let reading = LearnedWord.normalize(rawReading, mode: mode)
                    guard let id = index[IndexKey(mode: mode, reading: reading)]?.first(where: { words[$0]?.text == text }),
                          var word = words[id] else { continue }
                    word.count = max(0, word.count - 1)
                    if word.count == 0, word.kind == .learned, !word.pinned {
                        try database.run("DELETE FROM words WHERE id = ?", [.integer(id)])
                        removeFromMemory(id)
                    } else {
                        try database.run("UPDATE words SET count = ? WHERE id = ?", [.integer(Int64(word.count)), .integer(id)])
                        words[id] = word
                        try database.run("DELETE FROM events WHERE rowid = (SELECT MAX(rowid) FROM events WHERE word_id = ?)", [.integer(id)])
                    }
                }
            }
        } catch {
            Log.learning.error("Unlearning not saved: \(String(describing: error), privacy: .public)")
            try? loadAll()
        }
        notify()
    }

    /// The (reading, text) pairs a commit teaches: each converted clause and,
    /// when it is short enough to be a word, the whole commit.
    private static func pairs(learnedFrom commit: Commit) -> [(String, String)] {
        var pairs = commit.clauses.filter { $0.text != $0.reading }.map { ($0.reading, $0.text) }
        if commit.text.count <= maximumWordLength, commit.text != commit.reading, !pairs.contains(where: { $0.1 == commit.text }) {
            pairs.append((commit.reading, commit.text))
        }
        return pairs
    }

    /// Adds a word the user typed in, or imported.
    @discardableResult
    public func addUserWord(reading: String, text: String, mode: InputMode) -> Bool {
        let reading = LearnedWord.normalize(enteredReading: reading, mode: mode)
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
                let reading = LearnedWord.normalize(enteredReading: entry.reading, mode: entry.mode)
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

    /// Merges words from Sugu's own file (another Mac, or a sync folder).
    /// A word missing here is taken only when used after `since`, so a word
    /// deleted here is not brought back by an older copy. A word already in
    /// the store always merges and keeps
    /// the higher count, the later use, and its pin if either side has one.
    /// Returns how many words were new.
    @discardableResult
    public func merge(_ incoming: [LearnedWord], since: Date? = nil) throws -> Int {
        var added = 0
        try database.transaction {
            for word in incoming {
                let reading = LearnedWord.normalize(word.reading, mode: word.mode)
                guard !reading.isEmpty, !word.text.isEmpty else { continue }
                let wordKey = WordKey(mode: word.mode, reading: reading, text: word.text)
                if let deletion = deletions[wordKey] {
                    // Deleted here after this copy was last used: stay deleted.
                    guard word.lastUsed > deletion.deletedAt else { continue }
                    try forgetDeletion(wordKey)
                }
                let key = IndexKey(mode: word.mode, reading: reading)
                if let id = index[key]?.first(where: { words[$0]?.text == word.text }), var existing = words[id] {
                    // Words both sides have always merge, so a pin or more
                    // uses on another Mac arrive even without a newer use.
                    let before = existing
                    existing.count = max(existing.count, word.count)
                    existing.lastUsed = max(existing.lastUsed, word.lastUsed)
                    existing.firstUsed = min(existing.firstUsed, word.firstUsed)
                    existing.pinned = existing.pinned || word.pinned
                    if word.kind == .user { existing.kind = .user }
                    guard existing != before else { continue }
                    try database.run(
                        "UPDATE words SET count = ?, pinned = ?, kind = ?, first_used = ?, last_used = ? WHERE id = ?",
                        [.integer(Int64(existing.count)), .integer(existing.pinned ? 1 : 0), .integer(Int64(existing.kind.rawValue)),
                         .real(existing.firstUsed.timeIntervalSinceReferenceDate), .real(existing.lastUsed.timeIntervalSinceReferenceDate), .integer(id)]
                    )
                    words[id] = existing
                } else {
                    // A word missing here and not used since the last pull
                    // was deleted here (or expired); it stays gone.
                    if let since, word.lastUsed <= since { continue }
                    let id = try database.run(
                        "INSERT INTO words (mode, reading, text, kind, count, pinned, first_used, last_used) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                        [.text(word.mode.rawValue), .text(reading), .text(word.text), .integer(Int64(word.kind.rawValue)), .integer(Int64(word.count)),
                         .integer(word.pinned ? 1 : 0), .real(word.firstUsed.timeIntervalSinceReferenceDate), .real(word.lastUsed.timeIntervalSinceReferenceDate)]
                    )
                    var stored = word
                    stored.id = id
                    stored.reading = reading
                    insertInMemory(stored)
                    added += 1
                }
            }
        }
        notify()
        return added
    }

    /// Applies deletions made on another Mac: a copy here not used since
    /// the deletion is deleted. The deletion is remembered either way, so a
    /// third Mac's older copy is refused too. Returns how many words went.
    @discardableResult
    public func applyDeletions(_ incoming: [WordDeletion]) throws -> Int {
        var removed = 0
        try database.transaction {
            for deletion in incoming {
                let reading = LearnedWord.normalize(deletion.reading, mode: deletion.mode)
                let key = WordKey(mode: deletion.mode, reading: reading, text: deletion.text)
                if let known = deletions[key], known.deletedAt >= deletion.deletedAt { continue }
                if let id = index[IndexKey(mode: deletion.mode, reading: reading)]?.first(where: { words[$0]?.text == deletion.text }),
                   let word = words[id] {
                    // Used here after it was deleted there: keep it.
                    guard word.lastUsed <= deletion.deletedAt else { continue }
                    try database.run("DELETE FROM words WHERE id = ?", [.integer(id)])
                    removeFromMemory(id)
                    removed += 1
                }
                var stored = deletion
                stored.reading = reading
                try remember(stored)
            }
        }
        if removed > 0 { notify() }
        return removed
    }

    private func remember(_ deletion: WordDeletion) throws {
        try database.run(
            "INSERT OR REPLACE INTO deletions (mode, reading, text, kind, deleted_at) VALUES (?, ?, ?, ?, ?)",
            [.text(deletion.mode.rawValue), .text(deletion.reading), .text(deletion.text), .integer(Int64(deletion.kind.rawValue)),
             .real(deletion.deletedAt.timeIntervalSinceReferenceDate)]
        )
        deletions[WordKey(mode: deletion.mode, reading: deletion.reading, text: deletion.text)] = deletion
    }

    private func forgetDeletion(_ key: WordKey) throws {
        guard deletions.removeValue(forKey: key) != nil else { return }
        try database.run("DELETE FROM deletions WHERE mode = ? AND reading = ? AND text = ?",
                         [.text(key.mode.rawValue), .text(key.reading), .text(key.text)])
    }

    private func recordUse(reading rawReading: String, text: String, mode: InputMode, kind: LearnedWord.Kind, at now: Date, logEvent: Bool = true) throws {
        let reading = LearnedWord.normalize(rawReading, mode: mode)
        guard !reading.isEmpty, !text.isEmpty else { return }
        // Typing a deleted word again brings it back.
        try forgetDeletion(WordKey(mode: mode, reading: reading, text: text))
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

    /// Deletes words the user chose to delete; sync deletes them on other
    /// Macs too.
    public func delete(ids: [Int64]) {
        remove(ids: ids, propagate: true)
    }

    private func remove(ids: [Int64], propagate: Bool) {
        guard !ids.isEmpty else { return }
        let now = clock()
        try? database.transaction {
            for id in ids {
                guard let word = words[id] else { continue }
                try database.run("DELETE FROM words WHERE id = ?", [.integer(id)])
                removeFromMemory(id)
                if propagate {
                    try remember(WordDeletion(mode: word.mode, reading: word.reading, text: word.text, kind: word.kind, deletedAt: now))
                }
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
                    try remember(WordDeletion(mode: word.mode, reading: word.reading, text: word.text, kind: word.kind, deletedAt: clock()))
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
        // Expiry is local: another Mac may have used the word since.
        remove(ids: stale, propagate: false)
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
