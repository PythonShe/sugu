import Foundation
import os
import SuguCore
import Testing

/// The exported report carries the settings given and Sugu's log entries.
@Test func diagnosticsReportIncludesTheLog() async throws {
    let marker = UUID().uuidString
    Log.app.notice("Diagnostics test \(marker, privacy: .public)")
    let report = try await DiagnosticsReport.make(settings: Data("{\"pinyinScheme\":\"xiaohe\"}".utf8))
    #expect(report.hasPrefix("Sugu "))
    #expect(report.contains("\"pinyinScheme\":\"xiaohe\""))
    #expect(report.contains("[app] Diagnostics test \(marker)"))
}
