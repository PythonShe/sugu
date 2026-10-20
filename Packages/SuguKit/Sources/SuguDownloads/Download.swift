import Foundation

/// A file Sugu downloads on the user's request, pinned to a checksum so
/// that what arrives is exactly what was reviewed.
public struct Download: Sendable, Equatable {
    public var url: URL
    /// Tried when `url` does not answer with the file: where it was
    /// published first.
    public var fallback: URL?
    /// Lowercase hex SHA-256 of the file.
    public var sha256: String
    /// Expected size in bytes, for progress before the server reports one,
    /// and for the space it needs.
    public var size: Int64

    public init(url: URL, fallback: URL? = nil, sha256: String, size: Int64) {
        self.url = url
        self.fallback = fallback
        self.sha256 = sha256.lowercased()
        self.size = size
    }
}

public enum DownloadError: Error, Equatable {
    case server(status: Int)
    case checksumMismatch
    case extractionFailed
    /// The disk lacks room for the file.
    case notEnoughSpace
}
