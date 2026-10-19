import CryptoKit
import Foundation

/// Downloads a file, verifies its checksum, and leaves it at a destination.
/// Progress arrives on the main actor.
public enum Downloader {
    public static func fetch(
        _ download: Download,
        to destination: URL,
        session: URLSession = .shared,
        progress: @escaping @MainActor @Sendable (Double) -> Void = { _ in }
    ) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).partial")
        try? fm.removeItem(at: staging)
        defer { try? fm.removeItem(at: staging) }

        let delegate = ProgressDelegate(expected: download.size, progress: progress)
        let (location, response) = try await session.download(from: download.url, delegate: delegate)
        try fm.moveItem(at: location, to: staging)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.server(status: http.statusCode)
        }
        let digest = try await Task.detached(priority: .utility) { try sha256(of: staging) }.value
        guard digest == download.sha256 else { throw DownloadError.checksumMismatch }
        try? fm.removeItem(at: destination)
        try fm.moveItem(at: staging, to: destination)
    }

    /// Lowercase hex SHA-256 of a file, read in chunks.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let expected: Int64
    let progress: @MainActor @Sendable (Double) -> Void

    init(expected: Int64, progress: @escaping @MainActor @Sendable (Double) -> Void) {
        self.expected = expected
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expected
        guard total > 0 else { return }
        let fraction = min(1, Double(totalBytesWritten) / Double(total))
        let progress = progress
        Task { @MainActor in progress(fraction) }
    }

    /// Required by the protocol; the async API returns the file instead.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
