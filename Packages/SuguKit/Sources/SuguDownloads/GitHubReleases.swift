import Foundation

/// A downloadable file at a version: a pinned one, or one a release
/// lists with its checksum.
public struct Release: Sendable, Equatable {
    public var version: String
    public var download: Download
    /// When the file was uploaded; a file replaced later counts from then.
    public var uploaded: Date

    public init(version: String, download: Download, uploaded: Date = .distantPast) {
        self.version = version
        self.download = download
        self.uploaded = uploaded
    }
}

/// Upstream releases on GitHub, read from its releases API. GitHub's own
/// SHA-256 of each file pins the download.
public enum GitHubReleases {
    /// The newest file named `asset` that has been public for at least
    /// `minimumAge`: from the release tagged `tag`, or from the recent
    /// releases of `repository` whose tags match `versions` (which keeps
    /// out moving tags such as a nightly build).
    public static func newest(
        _ asset: String, in repository: String, tag: String? = nil, versions: Regex<Substring>? = nil,
        minimumAge: TimeInterval, now: Date = .now, session: URLSession = .shared
    ) async throws -> Release? {
        let path = tag.map { "releases/tags/\($0)" } ?? "releases?per_page=10"
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/\(path)")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.server(status: http.statusCode)
        }
        return try newest(asset, in: data, versions: versions, minimumAge: minimumAge, now: now)
    }

    /// The newest file named `asset` old enough in an API answer, which is
    /// one release or a list of them. Drafts, pre-releases and files
    /// without a checksum are passed over.
    public static func newest(_ asset: String, in data: Data, versions: Regex<Substring>? = nil, minimumAge: TimeInterval, now: Date) throws -> Release? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let releases = try (try? decoder.decode([APIRelease].self, from: data)) ?? [decoder.decode(APIRelease.self, from: data)]
        return releases
            .filter { release in
                !release.draft && !release.prerelease && (versions.map { release.tagName.wholeMatch(of: $0) != nil } ?? true)
            }
            .flatMap { release in
                release.assets.compactMap { file -> Release? in
                    guard file.name == asset, let digest = file.digest, digest.hasPrefix("sha256:") else { return nil }
                    let download = Download(url: file.browserDownloadUrl, sha256: String(digest.dropFirst("sha256:".count)), size: file.size)
                    return Release(version: release.tagName, download: download, uploaded: file.updatedAt)
                }
            }
            .filter { now.timeIntervalSince($0.uploaded) >= minimumAge }
            .max { $0.uploaded < $1.uploaded }
    }

    private struct APIRelease: Decodable {
        var tagName: String
        var draft: Bool
        var prerelease: Bool
        var assets: [APIAsset]
    }

    private struct APIAsset: Decodable {
        var name: String
        var size: Int64
        var digest: String?
        var updatedAt: Date
        var browserDownloadUrl: URL
    }
}
