import Foundation
import Testing

/// Three launches within a minute count as a crash loop; launches spread
/// out, or long ago, do not.
@Test func launchesCloseTogetherMakeALoop() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-launches-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    #expect(!LaunchHistory.recordLaunch(in: folder, now: start))
    #expect(!LaunchHistory.recordLaunch(in: folder, now: start + 90))
    #expect(!LaunchHistory.recordLaunch(in: folder, now: start + 100))
    #expect(LaunchHistory.recordLaunch(in: folder, now: start + 110))
    #expect(!LaunchHistory.recordLaunch(in: folder, now: start + 1_000))
}
