import CryptoKit
import Foundation
import Testing
import SuguDownloads
import SuguEngines

@MainActor
private final class StubHost: ModelHost {
    let locations: EngineHub.Locations
    var changes = 0

    init(root: URL) {
        locations = EngineHub.Locations(
            rimeShared: root.appendingPathComponent("shared"),
            rimeUser: root.appendingPathComponent("user"),
            azooKey: root.appendingPathComponent("azookey"),
            models: root.appendingPathComponent("models"),
            lexicon: root.appendingPathComponent("lexicon")
        )
    }

    func modelsDidChange() { changes += 1 }
}

@MainActor
@Suite struct ModelLibraryTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("sugu-models-\(UUID().uuidString)", isDirectory: true)

    /// A local file standing in for a pinned download.
    private func download(_ contents: String, checksum: String? = nil) throws -> Download {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source-\(UUID().uuidString)")
        let data = Data(contents.utf8)
        try data.write(to: source)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return Download(url: source, sha256: checksum ?? digest, size: Int64(data.count))
    }

    private func wait(for library: ModelLibrary, _ item: ModelLibrary.Item, until done: (ModelLibrary.State) -> Bool) async {
        for _ in 0..<500 where !done(library.state(of: item)) {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func installsAndRemovesAVerifiedDownload() async throws {
        let host = StubHost(root: root)
        let file = try download("gram")
        let library = ModelLibrary(engines: host, downloads: { _ in file })
        #expect(library.state(of: .grammarModel) == .notInstalled)

        library.install(.grammarModel)
        await wait(for: library, .grammarModel) { $0 == .installed }
        #expect(library.state(of: .grammarModel) == .installed)
        #expect(host.locations.hasGrammarModel)
        #expect(host.changes == 1)

        library.remove(.grammarModel)
        await wait(for: library, .grammarModel) { $0 == .notInstalled }
        #expect(!host.locations.hasGrammarModel)
        #expect(host.changes == 2)
    }

    @Test func aChecksumMismatchFailsAndInstallsNothing() async throws {
        let host = StubHost(root: root)
        let file = try download("gram", checksum: String(repeating: "0", count: 64))
        let library = ModelLibrary(engines: host, downloads: { _ in file })
        library.install(.zenzaiModel)
        await wait(for: library, .zenzaiModel) { if case .failed = $0 { true } else { false } }
        #expect(library.state(of: .zenzaiModel) == .failed(.checksumMismatch))
        #expect(!host.locations.hasZenzaiModel)
        #expect(host.changes == 0)
    }

    @Test func removingDuringADownloadLeavesNothingBehind() async throws {
        let host = StubHost(root: root)
        let file = try download(String(repeating: "g", count: 1 << 20))
        let library = ModelLibrary(engines: host, downloads: { _ in file })
        library.install(.grammarModel)
        library.remove(.grammarModel)
        // Installing again is refused until the removal has finished.
        library.install(.grammarModel)
        await wait(for: library, .grammarModel) { $0 == .notInstalled }
        try await Task.sleep(for: .milliseconds(100))
        #expect(library.state(of: .grammarModel) == .notInstalled)
        #expect(!host.locations.hasGrammarModel)
    }
}
