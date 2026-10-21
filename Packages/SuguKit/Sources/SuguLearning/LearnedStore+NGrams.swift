import Foundation
import SuguCore
import SuguLM

/// The user's character n-grams (D-079): the runs of characters in what
/// they commit through Sugu, with the text Sugu typed just before, never
/// text read from the document. Learned and forgotten with the words, and
/// kept in memory for the language models.
extension LearnedStore {
    /// The user's n-grams for a mode's language model, kept up to date.
    public func personalNGrams(for mode: InputMode) -> PersonalNGrams {
        if let existing = nGrams[mode] { return existing }
        let created = PersonalNGrams()
        nGrams[mode] = created
        return created
    }

    /// Whether any n-grams are stored.
    public var hasNGrams: Bool { nGramRows.values.contains { $0 > 0 } }

    func loadNGrams() throws {
        for grams in nGrams.values { grams.removeAll() }
        nGramRows = [:]
        try database.query("SELECT mode, gram, count FROM ngrams") { row in
            guard let mode = InputMode(rawValue: row.string(0)) else { return }
            personalNGrams(for: mode).add(row.string(1), count: Int(row.int(2)))
            nGramRows[mode, default: 0] += 1
        }
    }

    /// The n-grams a commit teaches; none when it was made without its
    /// context, which is how a commit opts out.
    private func grams(of commit: Commit, mode: InputMode) -> [String] {
        guard mode != .english, let context = commit.context else { return [] }
        // In Simplified for Chinese, the script the language models read.
        let form = { (text: String) in self.storedText(text, mode: mode) }
        return PersonalNGrams.grams(of: form(commit.text), after: form(context))
    }

    func learnNGrams(of commit: Commit, mode: InputMode, at now: Date) throws {
        let grams = grams(of: commit, mode: mode)
        guard !grams.isEmpty else { return }
        let model = personalNGrams(for: mode)
        let at = SQLiteDatabase.Value.real(now.timeIntervalSinceReferenceDate)
        for gram in grams {
            try database.run("""
                INSERT INTO ngrams (mode, gram, count, last_used) VALUES (?, ?, 1, ?)
                ON CONFLICT (mode, gram) DO UPDATE SET count = count + 1, last_used = excluded.last_used
                """, [.text(mode.rawValue), .text(gram), at])
            try database.run("INSERT INTO ngram_events (mode, gram, at) VALUES (?, ?, ?)", [.text(mode.rawValue), .text(gram), at])
            if model.count(of: gram) == 0 { nGramRows[mode, default: 0] += 1 }
            model.add(gram, count: 1)
        }
        try database.run("DELETE FROM ngram_events WHERE at < ?", [.real(now.addingTimeInterval(-7_200).timeIntervalSinceReferenceDate)])
        // A tenth over the limit before pruning, so pruning is rare.
        if let rows = nGramRows[mode], rows > maximumNGrams + maximumNGrams / 10 {
            try removeNGrams("""
                DELETE FROM ngrams WHERE rowid IN
                    (SELECT rowid FROM ngrams WHERE mode = ? ORDER BY last_used LIMIT ?)
                RETURNING mode, gram, count
                """, [.text(mode.rawValue), .integer(Int64(rows - maximumNGrams))])
        }
    }

    func unlearnNGrams(of commit: Commit, mode: InputMode) throws {
        for gram in grams(of: commit, mode: mode) {
            try use(gram, mode: mode, count: -1)
            try database.run("DELETE FROM ngram_events WHERE rowid = (SELECT MAX(rowid) FROM ngram_events WHERE mode = ? AND gram = ?)",
                             [.text(mode.rawValue), .text(gram)])
        }
    }

    func forgetNGrams(since cutoff: Double) throws {
        var recent: [(InputMode, String, Int)] = []
        try database.query("SELECT mode, gram, COUNT(*) FROM ngram_events WHERE at >= ? GROUP BY mode, gram", [.real(cutoff)]) { row in
            guard let mode = InputMode(rawValue: row.string(0)) else { return }
            recent.append((mode, row.string(1), Int(row.int(2))))
        }
        for (mode, gram, uses) in recent { try use(gram, mode: mode, count: -uses) }
        try database.run("DELETE FROM ngram_events WHERE at >= ?", [.real(cutoff)])
    }

    func expireNGrams(before cutoff: Date) throws {
        try database.transaction {
            try removeNGrams("DELETE FROM ngrams WHERE last_used < ? RETURNING mode, gram, count",
                             [.real(cutoff.timeIntervalSinceReferenceDate)])
        }
    }

    func deleteNGrams(mode: InputMode?) throws {
        try database.transaction {
            if let mode {
                try database.run("DELETE FROM ngrams WHERE mode = ?", [.text(mode.rawValue)])
                try database.run("DELETE FROM ngram_events WHERE mode = ?", [.text(mode.rawValue)])
            } else {
                try database.execute("DELETE FROM ngrams; DELETE FROM ngram_events;")
            }
        }
        for (key, grams) in nGrams where mode == nil || key == mode {
            grams.removeAll()
            nGramRows[key] = 0
        }
    }

    /// Changes a stored n-gram's count, deleting it at zero.
    private func use(_ gram: String, mode: InputMode, count delta: Int) throws {
        let model = personalNGrams(for: mode)
        let current = model.count(of: gram)
        guard current > 0 else { return }
        let count = max(0, current + delta)
        if count == 0 {
            _ = try database.run("DELETE FROM ngrams WHERE mode = ? AND gram = ?", [.text(mode.rawValue), .text(gram)])
            nGramRows[mode, default: 1] -= 1
        } else {
            _ = try database.run("UPDATE ngrams SET count = ? WHERE mode = ? AND gram = ?",
                                 [.integer(Int64(count)), .text(mode.rawValue), .text(gram)])
        }
        model.add(gram, count: count - current)
    }

    /// Runs a deletion that returns the mode, gram and count of each row it
    /// removed, and takes those out of memory.
    private func removeNGrams(_ sql: String, _ values: [SQLiteDatabase.Value]) throws {
        var removed: [(InputMode, String, Int)] = []
        try database.query(sql, values) { row in
            guard let mode = InputMode(rawValue: row.string(0)) else { return }
            removed.append((mode, row.string(1), Int(row.int(2))))
        }
        for (mode, gram, count) in removed {
            personalNGrams(for: mode).add(gram, count: -count)
            nGramRows[mode, default: 1] -= 1
        }
    }
}
