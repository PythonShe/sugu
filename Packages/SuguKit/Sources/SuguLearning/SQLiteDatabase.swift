import Foundation
import SQLite3

/// A small wrapper over the SQLite C API: prepared statements with
/// positional bindings, nothing more.
final class SQLiteDatabase {
    enum Error: Swift.Error, CustomStringConvertible {
        case sqlite(code: Int32, message: String)
        var description: String {
            switch self {
            case .sqlite(let code, let message): "SQLite error \(code): \(message)"
            }
        }

        /// The file is damaged or not a database, as opposed to a failure
        /// that can pass (locked, protected before first unlock, disk full).
        var isCorruption: Bool {
            switch self {
            case .sqlite(let code, _): code & 0xFF == SQLITE_CORRUPT || code & 0xFF == SQLITE_NOTADB
            }
        }
    }

    enum Value {
        case integer(Int64)
        case real(Double)
        case text(String)
        case null
    }

    private var handle: OpaquePointer?

    init(url: URL) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            // deinit runs after a throwing init too; it must not close again.
            handle = nil
            throw Error.sqlite(code: SQLITE_CANTOPEN, message: message)
        }
        // Another process holding the file briefly (a second Sugu during an
        // update) waits rather than fails; short, since commits write on
        // the main thread.
        sqlite3_busy_timeout(handle, 200)
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit { sqlite3_close(handle) }

    /// Throws a corruption error when SQLite's structural check fails.
    func checkIntegrity() throws {
        var result = ""
        try query("PRAGMA quick_check(1)") { result = $0.string(0) }
        guard result == "ok" else { throw Error.sqlite(code: SQLITE_CORRUPT, message: result) }
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
    }

    @discardableResult
    func run(_ sql: String, _ values: [Value] = []) throws -> Int64 {
        try withStatement(sql, values) { statement in
            let code = sqlite3_step(statement)
            guard code == SQLITE_DONE || code == SQLITE_ROW else { throw lastError() }
        }
        return sqlite3_last_insert_rowid(handle)
    }

    func query(_ sql: String, _ values: [Value] = [], row: (Row) throws -> Void) throws {
        try withStatement(sql, values) { statement in
            while true {
                let code = sqlite3_step(statement)
                if code == SQLITE_DONE { break }
                guard code == SQLITE_ROW else { throw lastError() }
                try row(Row(statement: statement))
            }
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var changes: Int { Int(sqlite3_changes(handle)) }

    private func withStatement(_ sql: String, _ values: [Value], _ body: (OpaquePointer) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .integer(let v): sqlite3_bind_int64(statement, index, v)
            case .real(let v): sqlite3_bind_double(statement, index, v)
            case .text(let v): sqlite3_bind_text(statement, index, v, -1, transient)
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        try body(statement)
    }

    private func lastError() -> Error {
        .sqlite(code: sqlite3_errcode(handle), message: String(cString: sqlite3_errmsg(handle)))
    }

    struct Row {
        let statement: OpaquePointer
        func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
        func double(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
        func string(_ column: Int32) -> String {
            guard let text = sqlite3_column_text(statement, column) else { return "" }
            return String(cString: text)
        }
    }
}
