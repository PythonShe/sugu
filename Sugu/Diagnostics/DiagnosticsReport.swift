import Foundation
import OSLog
import SuguCore

/// What Settings › Advanced › Diagnostics exports, for a bug report:
/// versions, settings, and Sugu's own latest log entries since it started.
/// Made only when the user asks and saved where they choose; nothing is
/// sent. The log is read off the main actor: after days of running it
/// takes a while, and the main actor serves keystrokes.
enum DiagnosticsReport {
    /// The newest entries kept.
    static let entryLimit = 5_000

    static func make(settings: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) { try report(settings: settings) }.value
    }

    private static func report(settings: Data) throws -> String {
        let bundle = Bundle.main
        var lines = [
            "Sugu \(bundle.shortVersion) (\(bundle.buildVersion))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "",
            String(decoding: settings, as: UTF8.self),
            "",
        ]
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", Log.subsystem))
        let dates = ISO8601DateFormatter()
        var log: [String] = []
        for case let entry as OSLogEntryLog in entries {
            log.append("\(dates.string(from: entry.date)) [\(entry.category)] \(entry.composedMessage)")
        }
        return (lines + log.suffix(entryLimit)).joined(separator: "\n") + "\n"
    }
}
