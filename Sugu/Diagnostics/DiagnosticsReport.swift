import Foundation
import OSLog
import SuguCore

/// What Settings › Advanced › Diagnostics exports, for a bug report:
/// versions, settings, and Sugu's own log entries since it started. Made
/// only when the user asks and saved where they choose; nothing is sent.
enum DiagnosticsReport {
    static func make(settings: Data) throws -> String {
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
        for case let entry as OSLogEntryLog in entries {
            lines.append("\(dates.string(from: entry.date)) [\(entry.category)] \(entry.composedMessage)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
