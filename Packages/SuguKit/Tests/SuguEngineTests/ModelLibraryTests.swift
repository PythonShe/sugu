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

    func modelDidChange(_ item: ModelLibrary.Item) { changes += 1 }
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

    private func until(_ done: () -> Bool) async {
        for _ in 0..<500 where !done() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func installsAndRemovesAVerifiedDownload() async throws {
        let host = StubHost(root: root)
        let file = try download("gram")
        let library = ModelLibrary(engines: host, pinned: { _ in Release(version: "1", download: file) }, latest: { _ in nil })
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
        let library = ModelLibrary(engines: host, pinned: { _ in Release(version: "1", download: file) }, latest: { _ in nil })
        library.install(.zenzaiModel)
        await wait(for: library, .zenzaiModel) { if case .failed = $0 { true } else { false } }
        #expect(library.state(of: .zenzaiModel) == .failed(.checksumMismatch))
        #expect(!host.locations.hasZenzaiModel)
        #expect(host.changes == 0)
    }

    @Test func removingDuringADownloadLeavesNothingBehind() async throws {
        let host = StubHost(root: root)
        let file = try download(String(repeating: "g", count: 1 << 20))
        let library = ModelLibrary(engines: host, pinned: { _ in Release(version: "1", download: file) }, latest: { _ in nil })
        library.install(.grammarModel)
        library.remove(.grammarModel)
        // Installing again is refused until the removal has finished.
        library.install(.grammarModel)
        await wait(for: library, .grammarModel) { $0 == .notInstalled }
        try await Task.sleep(for: .milliseconds(100))
        #expect(library.state(of: .grammarModel) == .notInstalled)
        #expect(!host.locations.hasGrammarModel)
    }

    @Test func offersAndInstallsANewerUpstreamRelease() async throws {
        let host = StubHost(root: root)
        let first = Release(version: "1", download: try download("gram 1"))
        let second = Release(version: "2", download: try download("gram 2"))
        var upstream: Release? = first
        let library = ModelLibrary(engines: host, pinned: { _ in first }, latest: { _ in upstream })
        library.install(.grammarModel)
        await wait(for: library, .grammarModel) { $0 == .installed }
        let installed = try #require(host.locations.grammarModel)

        library.checkForUpdates()
        try await Task.sleep(for: .milliseconds(100))
        #expect(library.updates[.grammarModel] == nil)

        upstream = second
        library.checkForUpdates(now: .now.addingTimeInterval(86_400))
        await until { library.updates[.grammarModel] != nil }
        #expect(library.updates[.grammarModel] == second)

        library.install(.grammarModel)
        await until { library.updates[.grammarModel] == nil && library.state(of: .grammarModel) == .installed }
        let updated = try #require(host.locations.grammarModel)
        // A new name, so octagram loads it; the old file is gone.
        #expect(updated != installed)
        #expect(try String(contentsOf: updated, encoding: .utf8) == "gram 2")
        #expect(!FileManager.default.fileExists(atPath: installed.path))
        #expect(host.changes == 2)

        // The installed version is remembered across launches.
        let relaunched = ModelLibrary(engines: host, pinned: { _ in first }, latest: { _ in second })
        relaunched.checkForUpdates()
        try await Task.sleep(for: .milliseconds(100))
        #expect(relaunched.updates[.grammarModel] == nil)
    }

    /// Zenzai follows Sugu's pin, not upstream.
    @Test func offersAPinnedFileThatChanged() async throws {
        let host = StubHost(root: root)
        let old = Release(version: "1", download: try download("zenzai 1"))
        let new = Release(version: "2", download: try download("zenzai 2"))
        let library = ModelLibrary(engines: host, pinned: { _ in old }, latest: { _ in nil })
        library.install(.zenzaiModel)
        await wait(for: library, .zenzaiModel) { $0 == .installed }

        let updated = ModelLibrary(engines: host, pinned: { _ in new }, latest: { _ in nil })
        updated.checkForUpdates()
        await until { updated.updates[.zenzaiModel] != nil }
        #expect(updated.updates[.zenzaiModel] == new)
    }

    @Test func aNewInstallTakesUpstreamOrFallsBackToThePin() async throws {
        let host = StubHost(root: root)
        let pinned = Release(version: "1", download: try download("pinned"))
        let upstream = Release(version: "2", download: try download("upstream"))
        let library = ModelLibrary(engines: host, pinned: { _ in pinned }, latest: { _ in upstream })
        library.install(.grammarModel)
        await wait(for: library, .grammarModel) { $0 == .installed }
        #expect(try String(contentsOf: #require(host.locations.grammarModel), encoding: .utf8) == "upstream")

        let offline = ModelLibrary(engines: host, pinned: { _ in pinned }, latest: { _ in throw URLError(.notConnectedToInternet) })
        offline.install(.zenzaiModel)
        await wait(for: offline, .zenzaiModel) { $0 == .installed }
        #expect(try String(contentsOf: host.locations.zenzaiModel, encoding: .utf8) == "pinned")
    }
}
