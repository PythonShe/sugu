import Foundation

/// A file Sugu downloads on the user's request, pinned to a checksum so
/// that what arrives is exactly what was reviewed.
public struct Download: Sendable, Equatable {
    public var url: URL
    /// Lowercase hex SHA-256 of the file.
    public var sha256: String
    /// Expected size in bytes, for progress before the server reports one.
    public var size: Int64

    public init(url: URL, sha256: String, size: Int64) {
        self.url = url
        self.sha256 = sha256.lowercased()
        self.size = size
    }
}

public enum DownloadError: Error, Equatable {
    case server(status: Int)
    case checksumMismatch
    case extractionFailed
}
