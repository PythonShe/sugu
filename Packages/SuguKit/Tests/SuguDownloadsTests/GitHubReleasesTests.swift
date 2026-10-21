import Foundation
import Testing
import SuguDownloads

@Suite struct GitHubReleasesTests {
    private let now = ISO8601DateFormatter().date(from: "2026-10-21T00:00:00Z")!
    private let twoWeeks: TimeInterval = 14 * 86_400

    private func release(_ tag: String, uploaded: String, digest: String? = "sha256:ab", name: String = "cn_dicts.zip", draft: Bool = false, prerelease: Bool = false) -> String {
        let digestField = digest.map { #""digest": "\#($0)","# } ?? ""
        return #"""
        {"tag_name": "\#(tag)", "draft": \#(draft), "prerelease": \#(prerelease), "assets": [
          {"name": "\#(name)", "size": 14, \#(digestField) "updated_at": "\#(uploaded)",
           "browser_download_url": "https://github.com/o/r/releases/download/\#(tag)/\#(name)"}]}
        """#
    }

    private func newest(_ releases: [String]) throws -> Release? {
        try GitHubReleases.newest("cn_dicts.zip", in: Data("[\(releases.joined(separator: ","))]".utf8), minimumAge: twoWeeks, now: now)
    }

    @Test func picksTheNewestFileOldEnough() throws {
        let found = try newest([
            release("2026.10.15", uploaded: "2026-10-15T06:00:00Z"),
            release("2026.09.30", uploaded: "2026-09-30T06:00:00Z"),
            release("2026.06.30", uploaded: "2026-06-30T06:00:00Z"),
        ])
        #expect(found?.version == "2026.09.30")
        #expect(found?.download.url.absoluteString == "https://github.com/o/r/releases/download/2026.09.30/cn_dicts.zip")
        #expect(found?.download.sha256 == "ab")
        #expect(found?.download.size == 14)
    }

    @Test func passesOverDraftsPrereleasesAndFilesWithoutAChecksum() throws {
        let found = try newest([
            release("draft", uploaded: "2026-09-01T00:00:00Z", draft: true),
            release("beta", uploaded: "2026-09-02T00:00:00Z", prerelease: true),
            release("unsigned", uploaded: "2026-09-03T00:00:00Z", digest: nil),
            release("md5", uploaded: "2026-09-04T00:00:00Z", digest: "md5:ab"),
            release("other", uploaded: "2026-09-05T00:00:00Z", name: "full.zip"),
            release("2026.06.30", uploaded: "2026-06-30T06:00:00Z"),
        ])
        #expect(found?.version == "2026.06.30")
    }

    @Test func keepsToTheVersionTags() throws {
        let data = Data("[\(release("nightly", uploaded: "2026-10-01T00:00:00Z")),\(release("2026.06.30", uploaded: "2026-06-30T06:00:00Z"))]".utf8)
        #expect(try GitHubReleases.newest("cn_dicts.zip", in: data, minimumAge: twoWeeks, now: now)?.version == "nightly")
        #expect(try GitHubReleases.newest("cn_dicts.zip", in: data, versions: /\d{4}\.\d{2}\.\d{2}/, minimumAge: twoWeeks, now: now)?.version == "2026.06.30")
    }

    /// A tag that moves (wanxiang's LTS) is one release, dated by its file.
    @Test func readsASingleReleaseByItsFilesDate() throws {
        let data = Data(release("LTS", uploaded: "2026-10-19T03:45:14Z").utf8)
        #expect(try GitHubReleases.newest("cn_dicts.zip", in: data, minimumAge: twoWeeks, now: now) == nil)
        let later = now.addingTimeInterval(twoWeeks)
        #expect(try GitHubReleases.newest("cn_dicts.zip", in: data, minimumAge: twoWeeks, now: later)?.version == "LTS")
    }
}
