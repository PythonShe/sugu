import os

/// Sugu's channels in the unified log, read with Console or `log show`
/// and exported only by the user. Lifecycle and failures only: never
/// readings, candidates, learned words, or text from a document.
public enum Log {
    public static let subsystem = "com.zheng-she.inputmethod.Sugu"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let engines = Logger(subsystem: subsystem, category: "engines")
    public static let input = Logger(subsystem: subsystem, category: "input")
    public static let learning = Logger(subsystem: subsystem, category: "learning")
    public static let sync = Logger(subsystem: subsystem, category: "sync")
    public static let downloads = Logger(subsystem: subsystem, category: "downloads")
}
