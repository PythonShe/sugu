import CryptoKit
import Foundation
import os

/// Downloads a file, verifies its checksum, and puts it at a destination
/// in one step, replacing what was there. Progress arrives on the main
/// actor, at most once per percent.
public enum Downloader {
    public static func fetch(
        _ download: Download,
        to destination: URL,
        session: URLSession = .sugu,
        progress: @escaping @MainActor @Sendable (Double) -> Void = { _ in }
    ) async throws {
        let fm = FileManager.default
        let folder = destination.deletingLastPathComponent()
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if let available = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           available < download.size {
            throw DownloadError.notEnoughSpace
        }
        let staging = folder.appendingPathComponent(".\(destination.lastPathComponent).partial")
        try? fm.removeItem(at: staging)
        defer { try? fm.removeItem(at: staging) }

        do {
            try await fetch(download.url, as: download, to: staging, session: session, progress: progress)
        } catch {
            // A server without the file, with another one under its name,
            // or out of reach; a cancel stays a cancel.
            guard let fallback = download.fallback, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { throw error }
            try? fm.removeItem(at: staging)
            try await fetch(fallback, as: download, to: staging, session: session, progress: progress)
        }
        // The checksum runs detached; a cancel during it must not install.
        try Task.checkCancellation()
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: destination)
        }
    }

    /// Downloads `url` to `staging` and checks it is the file `download` names.
    private static func fetch(
        _ url: URL, as download: Download, to staging: URL, session: URLSession,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws {
        let delegate = ProgressDelegate(expected: download.size, progress: progress)
        let (location, response) = try await session.download(from: url, delegate: delegate)
        try FileManager.default.moveItem(at: location, to: staging)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.server(status: http.statusCode)
        }
        let digest = try await Task.detached(priority: .utility) { try sha256(of: staging) }.value
        guard digest == download.sha256 else { throw DownloadError.checksumMismatch }
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

/// Reports progress in whole percents: URLSession reports every write,
/// hundreds of times a second, and the main actor also serves keystrokes.
private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let expected: Int64
    let progress: @MainActor @Sendable (Double) -> Void
    private let reported = OSAllocatedUnfairLock(initialState: -1)

    init(expected: Int64, progress: @escaping @MainActor @Sendable (Double) -> Void) {
        self.expected = expected
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expected
        guard total > 0 else { return }
        let fraction = min(1, Double(totalBytesWritten) / Double(total))
        let percent = Int(fraction * 100)
        let isNew = reported.withLock { last in
            guard percent > last else { return false }
            last = percent
            return true
        }
        guard isNew else { return }
        let progress = progress
        Task { @MainActor in progress(fraction) }
    }

    /// Required by the protocol; the async API returns the file instead.
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
