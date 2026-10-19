import Foundation
import Testing
@testable import SuguDownloads

@Suite struct DownloaderTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func verifiesAndMovesFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.bin")
        try Data("sugu".utf8).write(to: source)
        let digest = try Downloader.sha256(of: source)
        #expect(digest.count == 64)

        let destination = directory.appendingPathComponent("models/model.bin")
        try await Downloader.fetch(Download(url: source, sha256: digest, size: 4), to: destination)
        #expect(try Data(contentsOf: destination) == Data("sugu".utf8))
    }

    @Test func rejectsChecksumMismatch() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.bin")
        try Data("sugu".utf8).write(to: source)
        let destination = directory.appendingPathComponent("model.bin")
        await #expect(throws: DownloadError.checksumMismatch) {
            try await Downloader.fetch(Download(url: source, sha256: String(repeating: "0", count: 64), size: 4), to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func extractsZip() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let content = directory.appendingPathComponent("content")
        try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
        try Data("table".utf8).write(to: content.appendingPathComponent("base.dict.yaml"))
        let archive = directory.appendingPathComponent("a.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--keepParent", content.path, archive.path]
        try zip.run()
        zip.waitUntilExit()
        let out = directory.appendingPathComponent("out")
        try await ZipArchive.extract(archive, to: out)
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("content/base.dict.yaml").path))
    }
}
